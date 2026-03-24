# ============================================
# RDS PostgreSQL Database Configuration
# ============================================

# Security Group for RDS
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for LiteLLM RDS PostgreSQL database"
  vpc_id      = aws_default_vpc.default_vpc.id

  # Allow PostgreSQL access from ECS tasks only
  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks_sg.id]
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
    Name        = "${var.project_name}-rds-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# DB Subnet Group (for Multi-AZ deployment)
resource "aws_db_subnet_group" "litellm_db_subnet_group" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [
    aws_default_subnet.ecs_az1.id,
    aws_default_subnet.ecs_az2.id,
    aws_default_subnet.ecs_az3.id
  ]

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# RDS Parameter Group (optimized for LiteLLM)
resource "aws_db_parameter_group" "litellm_pg" {
  name   = "${var.project_name}-pg-params"
  family = "postgres16"

  # Connection settings
  parameter {
    name  = "max_connections"
    value = "200"
  }

  # Memory settings
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4096}" # 25% of available memory
  }

  # WAL settings for better performance
  parameter {
    name  = "wal_buffers"
    value = "2048"
  }

  # Logging (can be adjusted based on needs)
  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking more than 1 second
  }

  tags = {
    Name        = "${var.project_name}-pg-params"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Random password for RDS (stored in Terraform state)
resource "random_password" "db_password" {
  length  = 32
  special = true
  # Exclude characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>?"
}

# Store DB password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.project_name}/db_password"
  description = "LiteLLM RDS PostgreSQL password"

  tags = {
    Name        = "${var.project_name}-db-password"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "litellm_db" {
  identifier = "${var.project_name}-db"

  # Engine configuration
  engine               = "postgres"
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage # Enable storage autoscaling
  storage_type         = "gp3"
  storage_encrypted    = true

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.litellm_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false

  # High Availability
  multi_az = var.db_multi_az

  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window          = "03:00-04:00" # UTC
  maintenance_window     = "mon:04:00-mon:05:00" # UTC

  # Performance Insights
  performance_insights_enabled    = true
  performance_insights_retention_period = 7

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
  monitoring_role_arn            = aws_iam_role.rds_monitoring_role.arn

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.litellm_pg.name

  # Deletion protection
  deletion_protection = var.enable_deletion_protection
  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Apply changes immediately (set to false for production)
  apply_immediately = var.db_apply_immediately

  tags = {
    Name        = "${var.project_name}-db"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier # Ignore changes to snapshot identifier
    ]
  }
}

# IAM Role for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring_role" {
  name = "${var.project_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-rds-monitoring-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Alarms for RDS
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.project_name}-db-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.litellm_db.id
  }

  tags = {
    Name        = "${var.project_name}-db-cpu-alarm"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "database_memory" {
  alarm_name          = "${var.project_name}-db-freeable-memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "256000000" # 256 MB in bytes
  alarm_description   = "This metric monitors RDS freeable memory"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.litellm_db.id
  }

  tags = {
    Name        = "${var.project_name}-db-memory-alarm"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  alarm_name          = "${var.project_name}-db-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000000000" # 5 GB in bytes
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.litellm_db.id
  }

  tags = {
    Name        = "${var.project_name}-db-storage-alarm"
    Environment = var.environment
  }
}
