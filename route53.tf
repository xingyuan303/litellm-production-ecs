# ============================================
# Route53 and ACM Certificate Configuration
# ============================================

# Data source to get existing Route53 hosted zone
data "aws_route53_zone" "main" {
  count = var.enable_https ? 1 : 0
  name  = var.domain_name
}

# ACM Certificate for HTTPS
resource "aws_acm_certificate" "litellm_cert" {
  count = var.enable_https ? 1 : 0

  domain_name       = var.litellm_subdomain
  validation_method = "DNS"

  # Optional: Add Subject Alternative Names (SANs)
  subject_alternative_names = var.certificate_sans

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-certificate"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# DNS validation records for ACM certificate
resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_https ? {
    for dvo in aws_acm_certificate.litellm_cert[0].domain_validation_options : dvo.domain_name => {
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

# Certificate validation
resource "aws_acm_certificate_validation" "litellm_cert" {
  count = var.enable_https ? 1 : 0

  certificate_arn         = aws_acm_certificate.litellm_cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "10m"
  }
}

# A record pointing to ALB
resource "aws_route53_record" "litellm" {
  count = var.enable_https ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.litellm_subdomain
  type    = "A"

  alias {
    name                   = aws_lb.litellm_alb.dns_name
    zone_id                = aws_lb.litellm_alb.zone_id
    evaluate_target_health = true
  }
}

# Optional: AAAA record for IPv6 support
resource "aws_route53_record" "litellm_ipv6" {
  count = var.enable_https && var.enable_ipv6 ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.litellm_subdomain
  type    = "AAAA"

  alias {
    name                   = aws_lb.litellm_alb.dns_name
    zone_id                = aws_lb.litellm_alb.zone_id
    evaluate_target_health = true
  }
}

# Health check for the domain (optional but recommended)
resource "aws_route53_health_check" "litellm" {
  count = var.enable_https && var.enable_health_check ? 1 : 0

  fqdn              = var.litellm_subdomain
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name        = "${var.project_name}-health-check"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# CloudWatch alarm for Route53 health check
resource "aws_cloudwatch_metric_alarm" "health_check" {
  count = var.enable_https && var.enable_health_check ? 1 : 0

  alarm_name          = "${var.project_name}-route53-health-check"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "This metric monitors Route53 health check status"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    HealthCheckId = aws_route53_health_check.litellm[0].id
  }

  tags = {
    Name        = "${var.project_name}-route53-health-alarm"
    Environment = var.environment
  }
}
