# ============================================
# ECS Service Configuration (Updated with ALB)
# ============================================

resource "aws_ecs_service" "litellm_service" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.litellm_cluster.id
  task_definition = aws_ecs_task_definition.litellm_task.arn
  launch_type     = "FARGATE"

  # Initial desired count - will be managed by auto scaling
  desired_count = var.ecs_desired_count

  # Platform version (latest for Fargate)
  platform_version = "LATEST"

  # Network configuration
  network_configuration {
    subnets = [
      aws_default_subnet.ecs_az1.id,
      aws_default_subnet.ecs_az2.id,
      aws_default_subnet.ecs_az3.id
    ]
    security_groups  = [aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = true  # Required for pulling images from ECR
  }

  # Load balancer configuration
  load_balancer {
    target_group_arn = aws_lb_target_group.litellm_tg.arn
    container_name   = "litellm-container"
    container_port   = 4000
  }

  # Deployment configuration
  deployment_configuration {
    maximum_percent         = 200  # Allow 2x capacity during deployment
    minimum_healthy_percent = 100  # Maintain full capacity during deployment

    deployment_circuit_breaker {
      enable   = true   # Enable circuit breaker
      rollback = true   # Auto-rollback on failure
    }
  }

  # Health check grace period
  health_check_grace_period_seconds = 300

  # Enable ECS Exec for debugging
  enable_execute_command = var.enable_ecs_exec

  # Deployment controller
  deployment_controller {
    type = "ECS"  # Use ECS rolling update deployment
  }

  # Service discovery (optional - for internal communication)
  # Uncomment if you need service discovery
  # dynamic "service_registries" {
  #   for_each = var.enable_service_discovery ? [1] : []
  #   content {
  #     registry_arn = aws_service_discovery_service.litellm[0].arn
  #   }
  # }

  # Propagate tags from task definition to tasks
  propagate_tags = "TASK_DEFINITION"

  # Wait for load balancer to be ready
  depends_on = [
    aws_lb_listener.litellm_http,
    aws_lb_listener.litellm_https,
    aws_lb_listener.litellm_http_forward,
    aws_iam_role_policy_attachment.ecs_task_execution_policy
  ]

  tags = {
    Name        = "${var.project_name}-service"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  lifecycle {
    ignore_changes = [
      desired_count  # Managed by auto scaling
    ]
  }
}

# ============================================
# Optional: Service Discovery Configuration
# ============================================

# Private DNS namespace for service discovery
resource "aws_service_discovery_private_dns_namespace" "litellm" {
  count = var.enable_service_discovery ? 1 : 0

  name        = "${var.project_name}.local"
  description = "Private DNS namespace for LiteLLM service discovery"
  vpc         = aws_default_vpc.default_vpc.id

  tags = {
    Name        = "${var.project_name}-namespace"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Service discovery service
resource "aws_service_discovery_service" "litellm" {
  count = var.enable_service_discovery ? 1 : 0

  name = var.project_name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.litellm[0].id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name        = "${var.project_name}-discovery"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
