resource "aws_cloudwatch_metric_alarm" "blue_scale_out" {
  alarm_name          = "${var.app_name}-blue-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out blue when CPU > 70% for 2 mins"
  alarm_actions       = [aws_autoscaling_policy.blue_scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.blue.name
  }
}

resource "aws_cloudwatch_metric_alarm" "blue_scale_in" {
  alarm_name          = "${var.app_name}-blue-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in blue when CPU < 30% for 5 mins"
  alarm_actions       = [aws_autoscaling_policy.blue_scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.blue.name
  }
}

resource "aws_cloudwatch_metric_alarm" "green_scale_out" {
  alarm_name          = "${var.app_name}-green-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out green when CPU > 70% for 2 mins"
  alarm_actions       = [aws_autoscaling_policy.green_scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.green.name
  }
}

resource "aws_cloudwatch_metric_alarm" "green_scale_in" {
  alarm_name          = "${var.app_name}-green-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in green when CPU < 30% for 5 mins"
  alarm_actions       = [aws_autoscaling_policy.green_scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.green.name
  }
}

resource "aws_cloudwatch_log_group" "app_nginx_access" {
  name              = "/app/nginx/access"
  retention_in_days = 7
  skip_destroy      = true

  tags = {
    Name = "${var.app_name}-nginx-access-logs"
  }
}

resource "aws_cloudwatch_log_group" "app_nginx_error" {
  name              = "/app/nginx/error"
  retention_in_days = 7
  skip_destroy      = true

  tags = {
    Name = "${var.app_name}-nginx-error-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.app_name}-uptime-monitor"
  retention_in_days = 7

  tags = {
    Name = "${var.app_name}-lambda-logs"
  }
}
