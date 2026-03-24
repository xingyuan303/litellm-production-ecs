# ============================================
# IAM Roles and Policies
# ============================================

# ECS Task Execution Role (for ECS agent to pull images and logs)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-execution-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access
resource "aws_iam_role_policy" "ecs_task_execution_secrets_policy" {
  name = "${var.project_name}-ecs-secrets-policy"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.db_password.arn,
          "${var.openai_api_key != "" ? aws_secretsmanager_secret.openai_api_key[0].arn : ""}",
          "${var.anthropic_api_key != "" ? aws_secretsmanager_secret.anthropic_api_key[0].arn : ""}",
          "${var.azure_api_key != "" ? aws_secretsmanager_secret.azure_api_key[0].arn : ""}",
          "${var.gemini_api_key != "" ? aws_secretsmanager_secret.gemini_api_key[0].arn : ""}",
          "${var.aws_access_key_id != "" ? aws_secretsmanager_secret.aws_access_key[0].arn : ""}",
          "${var.aws_secret_access_key != "" ? aws_secretsmanager_secret.aws_secret_key[0].arn : ""}"
        ]
      }
    ]
  })
}

# ECS Task Role (for application to access AWS services)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ecs-task-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Policy for ECS Exec (debugging)
resource "aws_iam_role_policy" "ecs_task_exec_policy" {
  count = var.enable_ecs_exec ? 1 : 0

  name = "${var.project_name}-ecs-exec-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Optional: Policy for application to access S3, DynamoDB, etc.
# Uncomment and customize based on your needs
# resource "aws_iam_role_policy" "ecs_task_app_policy" {
#   name = "${var.project_name}-ecs-app-policy"
#   role = aws_iam_role.ecs_task_role.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "s3:GetObject",
#           "s3:PutObject"
#         ]
#         Resource = "arn:aws:s3:::your-bucket/*"
#       }
#     ]
#   })
# }
