# ============================================
# ECS Task Definition (Updated for Production)
# ============================================

resource "aws_ecs_task_definition" "litellm_task" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory

  # Task execution role (for pulling images and accessing Secrets Manager)
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  # Task role (for application permissions)
  task_role_arn = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "litellm-container"
      image = "${aws_ecr_repository.litellm_dev.repository_url}:latest"

      essential = true

      # Port mappings
      portMappings = [
        {
          containerPort = 4000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      # Environment variables
      environment = concat([
        {
          name  = "PORT"
          value = "4000"
        },
        {
          name  = "DATABASE_URL"
          value = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.litellm_db.endpoint}/${var.db_name}"
        },
        {
          name  = "LOG_LEVEL"
          value = var.litellm_log_level
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ],
      var.litellm_master_key != "" ? [
        {
          name  = "LITELLM_MASTER_KEY"
          value = var.litellm_master_key
        }
      ] : [],
      var.litellm_salt_key != "" ? [
        {
          name  = "LITELLM_SALT_KEY"
          value = var.litellm_salt_key
        }
      ] : [])

      # Secrets from AWS Secrets Manager
      # Note: AWS Bedrock uses IAM Role (task_role_arn) - no credentials needed!
      secrets = concat(
        var.openai_api_key != "" ? [
          {
            name      = "OPENAI_API_KEY"
            valueFrom = aws_secretsmanager_secret.openai_api_key[0].arn
          }
        ] : [],
        var.anthropic_api_key != "" ? [
          {
            name      = "ANTHROPIC_API_KEY"
            valueFrom = aws_secretsmanager_secret.anthropic_api_key[0].arn
          }
        ] : [],
        var.azure_api_key != "" ? [
          {
            name      = "AZURE_API_KEY"
            valueFrom = aws_secretsmanager_secret.azure_api_key[0].arn
          }
        ] : [],
        var.gemini_api_key != "" ? [
          {
            name      = "GEMINI_API_KEY"
            valueFrom = aws_secretsmanager_secret.gemini_api_key[0].arn
          }
        ] : []
      )

      # Health check
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:4000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # Logging configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.litellm_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Resource limits
      ulimits = [
        {
          name      = "nofile"
          softLimit = 65536
          hardLimit = 65536
        }
      ]

      # Linux parameters
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = {
    Name        = "${var.project_name}-task"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ============================================
# CloudWatch Log Group
# ============================================

resource "aws_cloudwatch_log_group" "litellm_logs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
