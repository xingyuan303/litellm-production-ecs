# ============================================
# Application Load Balancer Configuration
# ============================================

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for LiteLLM Application Load Balancer"
  vpc_id      = aws_default_vpc.default_vpc.id

  # Allow HTTP traffic from allowed CIDRs
  ingress {
    description = "HTTP from allowed CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Allow HTTPS traffic from allowed CIDRs
  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
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
    type             = "forward"
    target_group_arn = aws_lb_target_group.litellm_tg.arn
  }

  depends_on = [aws_acm_certificate_validation.litellm_cert]

  tags = {
    Name        = "${var.project_name}-https-listener"
    Environment = var.environment
  }
}

# HTTP Listener without HTTPS redirect (for testing)
resource "aws_lb_listener" "litellm_http_forward" {
  count = var.enable_https ? 0 : 1

  load_balancer_arn = aws_lb.litellm_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.litellm_tg.arn
  }

  tags = {
    Name        = "${var.project_name}-http-listener"
    Environment = var.environment
  }
}
