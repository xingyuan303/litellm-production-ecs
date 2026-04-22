# ============================================
# Application Load Balancer Configuration
# ============================================

# CloudFront managed prefix list (used to restrict ALB access)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = var.enable_cloudfront ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for LiteLLM Application Load Balancer"
  vpc_id      = aws_default_vpc.default_vpc.id

  # When CloudFront is enabled, only allow traffic from CloudFront
  dynamic "ingress" {
    for_each = var.enable_cloudfront ? [80] : []
    content {
      description     = "HTTP from CloudFront only"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront[0].id]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_cloudfront && var.enable_https ? [443] : []
    content {
      description     = "HTTPS from CloudFront only"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront[0].id]
    }
  }

  # When CloudFront is disabled, allow from specified CIDRs (fallback)
  dynamic "ingress" {
    for_each = var.enable_cloudfront ? [] : [80]
    content {
      description = "HTTP from allowed CIDRs"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidrs
    }
  }

  dynamic "ingress" {
    for_each = !var.enable_cloudfront && var.enable_https ? [443] : []
    content {
      description = "HTTPS from allowed CIDRs"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidrs
    }
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks_sg" {
  name        = "${var.project_name}-ecs-tasks-sg"
  description = "Security group for LiteLLM ECS tasks"
  vpc_id      = aws_default_vpc.default_vpc.id

  # Allow traffic from ALB on port 4000
  ingress {
    description     = "Allow traffic from ALB"
    from_port       = 4000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-ecs-tasks-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Application Load Balancer
resource "aws_lb" "litellm_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]

  subnets = [
    aws_default_subnet.ecs_az1.id,
    aws_default_subnet.ecs_az2.id,
    aws_default_subnet.ecs_az3.id
  ]

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "${var.project_name}-alb"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Target Group for ECS Service
resource "aws_lb_target_group" "litellm_tg" {
  name        = "${var.project_name}-tg"
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip" # Required for Fargate

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health/readiness"
    matcher             = "200"
    protocol            = "HTTP"
  }

  deregistration_delay = 30

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# HTTP Listener - Redirect to HTTPS
resource "aws_lb_listener" "litellm_http" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.litellm_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name        = "${var.project_name}-http-listener"
    Environment = var.environment
  }
}

# HTTPS Listener
resource "aws_lb_listener" "litellm_https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.litellm_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.enable_https ? aws_acm_certificate.litellm_cert[0].arn : null

  default_action {
    type = var.enable_cloudfront ? "fixed-response" : "forward"

    dynamic "fixed_response" {
      for_each = var.enable_cloudfront ? [1] : []
      content {
        content_type = "text/plain"
        message_body = "Forbidden"
        status_code  = "403"
      }
    }

    target_group_arn = var.enable_cloudfront ? null : aws_lb_target_group.litellm_tg.arn
  }

  depends_on = [aws_acm_certificate_validation.litellm_cert]

  tags = {
    Name        = "${var.project_name}-https-listener"
    Environment = var.environment
  }
}

# HTTPS Listener rule to validate CloudFront secret header
resource "aws_lb_listener_rule" "cloudfront_validated_https" {
  count = var.enable_cloudfront && var.enable_https ? 1 : 0

  listener_arn = aws_lb_listener.litellm_https[0].arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.litellm_tg.arn
  }

  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = [random_password.cloudfront_secret[0].result]
    }
  }
}

# HTTP Listener - when CloudFront is enabled, default action returns 403
# Only requests with valid CloudFront secret header are forwarded
resource "aws_lb_listener" "litellm_http_forward" {
  count = var.enable_https ? 0 : 1

  load_balancer_arn = aws_lb.litellm_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = var.enable_cloudfront ? "fixed-response" : "forward"

    dynamic "fixed_response" {
      for_each = var.enable_cloudfront ? [1] : []
      content {
        content_type = "text/plain"
        message_body = "Forbidden"
        status_code  = "403"
      }
    }

    target_group_arn = var.enable_cloudfront ? null : aws_lb_target_group.litellm_tg.arn
  }

  tags = {
    Name        = "${var.project_name}-http-listener"
    Environment = var.environment
  }
}

# Listener rule to validate CloudFront secret header and forward to target group
resource "aws_lb_listener_rule" "cloudfront_validated" {
  count = var.enable_cloudfront && !var.enable_https ? 1 : 0

  listener_arn = aws_lb_listener.litellm_http_forward[0].arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.litellm_tg.arn
  }

  condition {
    http_header {
      http_header_name = "X-CloudFront-Secret"
      values           = [random_password.cloudfront_secret[0].result]
    }
  }
}
