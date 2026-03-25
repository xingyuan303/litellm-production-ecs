# ============================================
# General Variables
# ============================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "litellm"
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources (ALB, RDS)"
  type        = bool
  default     = true
}

# ============================================
# ECS Configuration
# ============================================

variable "ecs_desired_count" {
  description = "Initial desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks for auto scaling"
  type        = number
  default     = 2
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks for auto scaling"
  type        = number
  default     = 10
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 4096
}

variable "ecs_task_memory" {
  description = "Memory for ECS task in MB"
  type        = number
  default     = 8192
}

variable "enable_ecs_exec" {
  description = "Enable ECS Exec for debugging"
  type        = bool
  default     = false
}

variable "enable_service_discovery" {
  description = "Enable AWS Cloud Map service discovery"
  type        = bool
  default     = false
}

# ============================================
# Auto Scaling Configuration
# ============================================

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto scaling"
  type        = number
  default     = 70
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for auto scaling"
  type        = number
  default     = 75
}

variable "alb_request_count_target" {
  description = "Target number of requests per target for auto scaling"
  type        = number
  default     = 1000
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling for predictable traffic patterns"
  type        = bool
  default     = false
}

variable "scheduled_scale_up_min" {
  description = "Minimum capacity during scale-up period"
  type        = number
  default     = 4
}

variable "scheduled_scale_up_max" {
  description = "Maximum capacity during scale-up period"
  type        = number
  default     = 10
}

variable "scheduled_scale_down_min" {
  description = "Minimum capacity during scale-down period"
  type        = number
  default     = 2
}

variable "scheduled_scale_down_max" {
  description = "Maximum capacity during scale-down period"
  type        = number
  default     = 4
}

# ============================================
# RDS Database Configuration
# ============================================

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "Maximum storage for autoscaling in GB"
  type        = number
  default     = 500
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "litellm"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "litellm_admin"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS instance (NOT recommended for production)"
  type        = bool
  default     = false
}

variable "db_apply_immediately" {
  description = "Apply database changes immediately (set to false for production)"
  type        = bool
  default     = false
}

# ============================================
# Domain and SSL Configuration
# ============================================

variable "enable_https" {
  description = "Enable HTTPS with ACM certificate and Route53"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Root domain name (must have existing Route53 hosted zone)"
  type        = string
  default     = ""
}

variable "litellm_subdomain" {
  description = "Full subdomain for LiteLLM (e.g., litellm.example.com)"
  type        = string
  default     = ""
}

variable "certificate_sans" {
  description = "Subject Alternative Names for ACM certificate"
  type        = list(string)
  default     = []
}

variable "enable_ipv6" {
  description = "Enable IPv6 support for Route53 records"
  type        = bool
  default     = false
}

variable "enable_health_check" {
  description = "Enable Route53 health check"
  type        = bool
  default     = false
}

# ============================================
# LiteLLM Configuration
# ============================================

variable "litellm_master_key" {
  description = "Master key for LiteLLM (should start with 'sk-')"
  type        = string
  sensitive   = true
  default     = ""
}

variable "litellm_salt_key" {
  description = "Salt key for LiteLLM encryption"
  type        = string
  sensitive   = true
  default     = ""
}

variable "litellm_log_level" {
  description = "Log level for LiteLLM (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
}

variable "enable_detailed_debug" {
  description = "Enable detailed debug mode (NOT recommended for production)"
  type        = bool
  default     = false
}

# ============================================
# API Keys Configuration
# ============================================

variable "openai_api_key" {
  description = "OpenAI API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "anthropic_api_key" {
  description = "Anthropic (Claude) API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "azure_api_key" {
  description = "Azure OpenAI API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gemini_api_key" {
  description = "Google Gemini API key"
  type        = string
  sensitive   = true
  default     = ""
}

# AWS Bedrock credentials are NO LONGER NEEDED
# LiteLLM will use the ECS Task IAM Role to access Bedrock
# This is more secure - no long-term credentials to manage!
#
# variable "aws_access_key_id" {
#   description = "AWS Access Key ID for Bedrock (DEPRECATED - use IAM Role)"
#   type        = string
#   sensitive   = true
#   default     = ""
# }
#
# variable "aws_secret_access_key" {
#   description = "AWS Secret Access Key for Bedrock (DEPRECATED - use IAM Role)"
#   type        = string
#   sensitive   = true
#   default     = ""
# }

# ============================================
# Monitoring and Alerting
# ============================================

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms (leave empty to disable notifications)"
  type        = string
  default     = ""
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
}

# ============================================
# Tags
# ============================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
