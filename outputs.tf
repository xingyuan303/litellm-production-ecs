# ============================================
# Outputs - Access Information
# ============================================

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.litellm_alb.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.litellm_alb.arn
}

output "alb_url_http" {
  description = "HTTP URL to access LiteLLM"
  value       = "http://${aws_lb.litellm_alb.dns_name}"
}

output "alb_url_https" {
  description = "HTTPS URL to access LiteLLM (if HTTPS is enabled)"
  value       = var.enable_https ? "https://${var.litellm_subdomain}" : "HTTPS not enabled"
}

output "custom_domain_url" {
  description = "Custom domain URL for LiteLLM"
  value       = var.enable_https ? "https://${var.litellm_subdomain}" : "Custom domain not configured"
}

# ============================================
# Outputs - Database Information
# ============================================

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.litellm_db.endpoint
  sensitive   = true
}

output "rds_address" {
  description = "RDS instance address (hostname)"
  value       = aws_db_instance.litellm_db.address
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.litellm_db.port
}

output "database_url" {
  description = "PostgreSQL connection string for LiteLLM"
  value       = "postgresql://${var.db_username}:${urlencode(random_password.db_password.result)}@${aws_db_instance.litellm_db.address}:${aws_db_instance.litellm_db.port}/${var.db_name}"
  sensitive   = true
}

output "db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the database password"
  value       = aws_secretsmanager_secret.db_password.arn
}

# ============================================
# Outputs - ECS Information
# ============================================

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.litellm_cluster.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.litellm_cluster.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.litellm_service.name
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.litellm_task.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.litellm_dev.repository_url
}

# ============================================
# Outputs - Security Groups
# ============================================

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb_sg.id
}

output "ecs_tasks_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks_sg.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds_sg.id
}

# ============================================
# Outputs - Auto Scaling
# ============================================

output "autoscaling_target_id" {
  description = "ID of the auto scaling target"
  value       = aws_appautoscaling_target.ecs_target.id
}

output "autoscaling_min_capacity" {
  description = "Minimum capacity for auto scaling"
  value       = var.ecs_min_capacity
}

output "autoscaling_max_capacity" {
  description = "Maximum capacity for auto scaling"
  value       = var.ecs_max_capacity
}

# ============================================
# Outputs - Monitoring
# ============================================

output "cloudwatch_log_group" {
  description = "CloudWatch log group name for ECS tasks"
  value       = aws_cloudwatch_log_group.litellm_logs.name
}

output "cloudwatch_log_stream_prefix" {
  description = "CloudWatch log stream prefix"
  value       = "ecs"
}

# ============================================
# Outputs - Route53 (if enabled)
# ============================================

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = var.enable_https ? data.aws_route53_zone.main[0].zone_id : "HTTPS not enabled"
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = var.enable_https ? aws_acm_certificate.litellm_cert[0].arn : "HTTPS not enabled"
}

# ============================================
# Outputs - Quick Start Commands
# ============================================

output "quick_start_commands" {
  description = "Quick start commands for common operations"
  value = <<-EOT

  ====================================
  LiteLLM Deployment Complete! 🚀
  ====================================

  Access URL:
  ${var.enable_https ? "  - HTTPS: https://${var.litellm_subdomain}" : "  - HTTP: http://${aws_lb.litellm_alb.dns_name}"}

  Database Connection:
    - Endpoint: ${aws_db_instance.litellm_db.endpoint}
    - Database: ${var.db_name}
    - Username: ${var.db_username}
    - Password: Stored in Secrets Manager (${aws_secretsmanager_secret.db_password.name})

  Common AWS CLI Commands:

  1. View ECS Service Status:
     aws ecs describe-services \\
       --cluster ${aws_ecs_cluster.litellm_cluster.name} \\
       --services ${aws_ecs_service.litellm_service.name} \\
       --region ${var.aws_region}

  2. View Running Tasks:
     aws ecs list-tasks \\
       --cluster ${aws_ecs_cluster.litellm_cluster.name} \\
       --region ${var.aws_region}

  3. View CloudWatch Logs:
     aws logs tail ${aws_cloudwatch_log_group.litellm_logs.name} \\
       --follow \\
       --region ${var.aws_region}

  4. Get Database Password from Secrets Manager:
     aws secretsmanager get-secret-value \\
       --secret-id ${aws_secretsmanager_secret.db_password.name} \\
       --query SecretString \\
       --output text \\
       --region ${var.aws_region}

  5. Force New Deployment (after updating Docker image):
     aws ecs update-service \\
       --cluster ${aws_ecs_cluster.litellm_cluster.name} \\
       --service ${aws_ecs_service.litellm_service.name} \\
       --force-new-deployment \\
       --region ${var.aws_region}

  6. Scale Service Manually:
     aws ecs update-service \\
       --cluster ${aws_ecs_cluster.litellm_cluster.name} \\
       --service ${aws_ecs_service.litellm_service.name} \\
       --desired-count 5 \\
       --region ${var.aws_region}

  7. Test Health Endpoint:
     curl ${var.enable_https ? "https://${var.litellm_subdomain}" : "http://${aws_lb.litellm_alb.dns_name}"}/health/readiness

  8. Test API (replace <your-key> with actual key):
     curl ${var.enable_https ? "https://${var.litellm_subdomain}" : "http://${aws_lb.litellm_alb.dns_name}"}/v1/models \\
       -H "Authorization: Bearer <your-key>"

  ====================================

  EOT
}

# ============================================
# Outputs - Connection Details for TaskDefinition Update
# ============================================

output "database_connection_env" {
  description = "Database connection string formatted for ECS environment variable"
  value = {
    name  = "DATABASE_URL"
    value = "postgresql://${var.db_username}:${urlencode(random_password.db_password.result)}@${aws_db_instance.litellm_db.address}:${aws_db_instance.litellm_db.port}/${var.db_name}"
  }
  sensitive = true
}

# ============================================
# Outputs - Project Configuration
# ============================================

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# ============================================
# Outputs - Network Information
# ============================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_default_vpc.default_vpc.id
}

output "default_subnet_az1_id" {
  description = "Subnet ID for availability zone 1"
  value       = aws_default_subnet.ecs_az1.id
}

output "default_subnet_az2_id" {
  description = "Subnet ID for availability zone 2"
  value       = aws_default_subnet.ecs_az2.id
}

output "default_subnet_az3_id" {
  description = "Subnet ID for availability zone 3"
  value       = aws_default_subnet.ecs_az3.id
}

# ============================================
# Outputs - CloudFront (if enabled)
# ============================================

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.litellm[0].id : "CloudFront not enabled"
}

output "cloudfront_distribution_arn" {
  description = "CloudFront Distribution ARN"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.litellm[0].arn : "CloudFront not enabled"
}

output "cloudfront_domain_name" {
  description = "CloudFront Distribution Domain Name (default)"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.litellm[0].domain_name : "CloudFront not enabled"
}

output "cloudfront_url" {
  description = "CloudFront URL (using default domain)"
  value       = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.litellm[0].domain_name}" : "CloudFront not enabled"
}

output "cloudfront_custom_domain_url" {
  description = "CloudFront Custom Domain URL (if configured)"
  value       = var.enable_cloudfront && var.cloudfront_custom_domain != "" ? "https://${var.cloudfront_custom_domain}" : "CloudFront custom domain not configured"
}

output "cloudfront_certificate_arn" {
  description = "ARN of the CloudFront ACM certificate (us-east-1)"
  value       = var.enable_cloudfront && var.cloudfront_custom_domain != "" && var.enable_https ? aws_acm_certificate.cloudfront_cert[0].arn : "CloudFront custom domain not configured"
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID (if enabled)"
  value       = var.enable_cloudfront && var.enable_waf ? aws_wafv2_web_acl.litellm[0].id : "WAF not enabled"
}

output "recommended_access_url" {
  description = "Recommended URL to access LiteLLM (prefers CloudFront custom domain > CloudFront default > ALB custom > ALB direct)"
  value = var.enable_cloudfront && var.cloudfront_custom_domain != "" ? "https://${var.cloudfront_custom_domain}" : (
    var.enable_cloudfront ? "https://${aws_cloudfront_distribution.litellm[0].domain_name}" : (
      var.enable_https ? "https://${var.litellm_subdomain}" : "http://${aws_lb.litellm_alb.dns_name}"
    )
  )
}
