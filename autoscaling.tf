# ============================================
# Auto Scaling Configuration for ECS Service
# ============================================

# Auto Scaling Target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.litellm_cluster.name}/${aws_ecs_service.litellm_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.litellm_service]
}

# ============================================
# CPU-based Auto Scaling Policy
# ============================================

resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  name               = "${var.project_name}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_value
    scale_in_cooldown  = 300  # 5 minutes
    scale_out_cooldown = 60   # 1 minute

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# ============================================
# Memory-based Auto Scaling Policy
# ============================================

resource "aws_appautoscaling_policy" "ecs_memory_policy" {
  name               = "${var.project_name}-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.memory_target_value
    scale_in_cooldown  = 300  # 5 minutes
    scale_out_cooldown = 60   # 1 minute

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# ============================================
# ALB Request Count-based Auto Scaling Policy
# ============================================

resource "aws_appautoscaling_policy" "ecs_alb_request_count_policy" {
  name               = "${var.project_name}-alb-request-count-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.alb_request_count_target
    scale_in_cooldown  = 300  # 5 minutes
    scale_out_cooldown = 60   # 1 minute

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.litellm_alb.arn_suffix}/${aws_lb_target_group.litellm_tg.arn_suffix}"
    }
  }
}

# ============================================
# Scheduled Scaling (Optional - for predictable traffic patterns)
# ============================================

# Scale up during business hours (example: 8 AM UTC)
resource "aws_appautoscaling_scheduled_action" "scale_up_morning" {
  count = var.enable_scheduled_scaling ? 1 : 0

  name               = "${var.project_name}-scale-up-morning"
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  schedule           = "cron(0 8 * * ? *)" # 8 AM UTC every day

  scalable_target_action {
    min_capacity = var.scheduled_scale_up_min
    max_capacity = var.scheduled_scale_up_max
  }
}

# Scale down during off-hours (example: 8 PM UTC)
resource "aws_appautoscaling_scheduled_action" "scale_down_evening" {
  count = var.enable_scheduled_scaling ? 1 : 0

  name               = "${var.project_name}-scale-down-evening"
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  schedule           = "cron(0 20 * * ? *)" # 8 PM UTC every day

  scalable_target_action {
    min_capacity = var.scheduled_scale_down_min
    max_capacity = var.scheduled_scale_down_max
  }
}

# ============================================
# CloudWatch Alarms for Scaling Events
# ============================================

# Alarm when service is at max capacity
resource "aws_cloudwatch_metric_alarm" "ecs_max_capacity" {
  alarm_name          = "${var.project_name}-ecs-max-capacity"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "DesiredTaskCount"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.ecs_max_capacity
  alarm_description   = "ECS service has reached maximum capacity"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    ServiceName = aws_ecs_service.litellm_service.name
    ClusterName = aws_ecs_cluster.litellm_cluster.name
  }

  tags = {
    Name        = "${var.project_name}-max-capacity-alarm"
    Environment = var.environment
  }
}

# Alarm for high CPU utilization (warning before scaling)
resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  alarm_name          = "${var.project_name}-ecs-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "ECS service CPU utilization is high"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    ServiceName = aws_ecs_service.litellm_service.name
    ClusterName = aws_ecs_cluster.litellm_cluster.name
  }

  tags = {
    Name        = "${var.project_name}-high-cpu-alarm"
    Environment = var.environment
  }
}

# Alarm for high memory utilization
resource "aws_cloudwatch_metric_alarm" "ecs_high_memory" {
  alarm_name          = "${var.project_name}-ecs-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "ECS service memory utilization is high"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    ServiceName = aws_ecs_service.litellm_service.name
    ClusterName = aws_ecs_cluster.litellm_cluster.name
  }

  tags = {
    Name        = "${var.project_name}-high-memory-alarm"
    Environment = var.environment
  }
}

# Alarm for ALB target health
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  alarm_name          = "${var.project_name}-alb-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "ALB has unhealthy targets"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    TargetGroup  = aws_lb_target_group.litellm_tg.arn_suffix
    LoadBalancer = aws_lb.litellm_alb.arn_suffix
  }

  tags = {
    Name        = "${var.project_name}-unhealthy-targets-alarm"
    Environment = var.environment
  }
}

# Alarm for ALB 5XX errors
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "ALB is receiving high number of 5XX errors"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.litellm_tg.arn_suffix
    LoadBalancer = aws_lb.litellm_alb.arn_suffix
  }

  tags = {
    Name        = "${var.project_name}-5xx-errors-alarm"
    Environment = var.environment
  }
}

# Alarm for ALB response time
resource "aws_cloudwatch_metric_alarm" "alb_high_response_time" {
  alarm_name          = "${var.project_name}-alb-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"  # 5 seconds
  alarm_description   = "ALB target response time is high"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    LoadBalancer = aws_lb.litellm_alb.arn_suffix
  }

  tags = {
    Name        = "${var.project_name}-high-response-time-alarm"
    Environment = var.environment
  }
}
