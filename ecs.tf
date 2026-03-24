# ============================================
# ECS Cluster Configuration
# ============================================

resource "aws_ecs_cluster" "litellm_cluster" {
  name = "${var.project_name}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-ecs-cluster"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Cluster Capacity Providers (Fargate)
resource "aws_ecs_cluster_capacity_providers" "litellm_cluster" {
  cluster_name = aws_ecs_cluster.litellm_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}
