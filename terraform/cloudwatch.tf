resource "aws_cloudwatch_metric_alarm" "scale_out" {
  alarm_name          = "${var.app_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when CPU > 70% for 2 mins"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_in" {
  alarm_name          = "${var.app_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in when CPU < 30% for 5 mins"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
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