# ============================================
# CloudFront Distribution for LiteLLM API
# 用于加速全球访问，特别是亚洲等远程地区
# ============================================

# 生成随机密钥（用于验证请求来自 CloudFront）
resource "random_password" "cloudfront_secret" {
  count   = var.enable_cloudfront ? 1 : 0
  length  = 32
  special = false
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "litellm" {
  count   = var.enable_cloudfront ? 1 : 0
  enabled = true
  comment = "${var.project_name} LiteLLM API Distribution"

  # 使用自定义域名（如果配置）
  aliases = var.cloudfront_custom_domain != "" && var.enable_https ? [var.cloudfront_custom_domain] : []

  # Origin - 指向 ALB
  origin {
    domain_name = aws_lb.litellm_alb.dns_name
    origin_id   = "ALB-${var.project_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = var.enable_https ? "https-only" : "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]

      # 保持长连接
      origin_keepalive_timeout = 60
      origin_read_timeout      = 60
    }

    # 自定义请求头（用于验证请求来自 CloudFront）
    custom_header {
      name  = "X-CloudFront-Secret"
      value = random_password.cloudfront_secret[0].result
    }
  }

  # 默认缓存行为 - 针对 API 请求（不缓存）
  default_cache_behavior {
    target_origin_id       = "ALB-${var.project_name}"
    viewer_protocol_policy = var.enable_https ? "redirect-to-https" : "allow-all"

    # 允许的 HTTP 方法
    allowed_methods = var.cloudfront_allowed_methods
    cached_methods  = var.cloudfront_cached_methods

    # 转发所有内容到源（API 不缓存响应）
    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }

    # 不缓存 API 响应
    min_ttl     = var.cloudfront_min_ttl
    default_ttl = var.cloudfront_default_ttl
    max_ttl     = var.cloudfront_max_ttl

    # 压缩响应
    compress = true
  }

  # 针对健康检查端点的缓存策略（可缓存）
  ordered_cache_behavior {
    path_pattern           = "/health/*"
    target_origin_id       = "ALB-${var.project_name}"
    viewer_protocol_policy = "allow-all"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      headers      = []
      cookies {
        forward = "none"
      }
    }

    # 缓存健康检查 30 秒
    min_ttl     = 0
    default_ttl = 30
    max_ttl     = 60
    compress    = true
  }

  # 地理限制
  restrictions {
    geo_restriction {
      restriction_type = var.cloudfront_geo_restriction_type
      locations        = var.cloudfront_geo_restriction_locations
    }
  }

  # SSL/TLS 证书配置
  viewer_certificate {
    # 如果使用自定义域名
    acm_certificate_arn      = var.cloudfront_custom_domain != "" && var.enable_https ? aws_acm_certificate.cloudfront_cert[0].arn : null
    ssl_support_method       = var.cloudfront_custom_domain != "" && var.enable_https ? "sni-only" : null
    minimum_protocol_version = "TLSv1.2_2021"

    # 如果使用默认 CloudFront 域名
    cloudfront_default_certificate = var.cloudfront_custom_domain == "" || !var.enable_https ? true : false
  }

  # 价格等级
  # PriceClass_All = 全球所有边缘节点
  # PriceClass_200 = 美洲、欧洲、亚洲、中东、非洲
  # PriceClass_100 = 美洲和欧洲
  price_class = var.cloudfront_price_class

  # 日志配置（可选）
  dynamic "logging_config" {
    for_each = var.cloudfront_logging_bucket != "" ? [1] : []
    content {
      include_cookies = false
      bucket          = "${var.cloudfront_logging_bucket}.s3.amazonaws.com"
      prefix          = "cloudfront-logs/"
    }
  }

  # WAF Web ACL（如果启用）
  web_acl_id = var.enable_waf ? aws_wafv2_web_acl.litellm[0].arn : null

  tags = {
    Name = "${var.project_name}-cloudfront"
  }

  # 等待部署完成（可能需要 15-20 分钟）
  wait_for_deployment = false
}

# ============================================
# CloudFront 专用 ACM 证书（必须在 us-east-1）
# ============================================

resource "aws_acm_certificate" "cloudfront_cert" {
  count    = var.enable_cloudfront && var.cloudfront_custom_domain != "" && var.enable_https ? 1 : 0
  provider = aws.us_east_1

  domain_name       = var.cloudfront_custom_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cloudfront-cert"
  }
}

# DNS 验证记录（用于 ACM 证书验证）
resource "aws_route53_record" "cloudfront_cert_validation" {
  for_each = var.enable_cloudfront && var.cloudfront_custom_domain != "" && var.enable_https ? {
    for dvo in aws_acm_certificate.cloudfront_cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main[0].zone_id
}

# 等待证书验证完成
resource "aws_acm_certificate_validation" "cloudfront_cert" {
  count    = var.enable_cloudfront && var.cloudfront_custom_domain != "" && var.enable_https ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront_cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cloudfront_cert_validation : record.fqdn]
}

# ============================================
# Route53 记录（如果使用自定义域名）
# ============================================

resource "aws_route53_record" "cloudfront" {
  count   = var.enable_cloudfront && var.cloudfront_custom_domain != "" && var.enable_https ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.cloudfront_custom_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.litellm[0].domain_name
    zone_id                = aws_cloudfront_distribution.litellm[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# AAAA 记录（IPv6 支持）
resource "aws_route53_record" "cloudfront_ipv6" {
  count   = var.enable_cloudfront && var.cloudfront_custom_domain != "" && var.enable_https && var.enable_ipv6 ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.cloudfront_custom_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.litellm[0].domain_name
    zone_id                = aws_cloudfront_distribution.litellm[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# ============================================
# WAF for CloudFront（可选）
# ============================================

resource "aws_wafv2_web_acl" "litellm" {
  count    = var.enable_cloudfront && var.enable_waf ? 1 : 0
  provider = aws.us_east_1  # WAF for CloudFront 必须在 us-east-1

  name  = "${var.project_name}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # 规则 1: 限速（防止滥用）
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # 规则 2: AWS 托管规则 - 通用防护
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # 规则 3: AWS 托管规则 - 已知恶意输入
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-waf"
  }
}
