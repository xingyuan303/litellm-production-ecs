# ============================================
# ECR (Elastic Container Registry) Configuration
# ============================================

resource "aws_ecr_repository" "litellm_dev" {
  name                 = "${var.project_name}-dev"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}-ecr"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Lifecycle policy to keep only recent images
resource "aws_ecr_lifecycle_policy" "litellm_dev" {
  repository = aws_ecr_repository.litellm_dev.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 3 untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 3
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
