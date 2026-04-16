resource "aws_sns_topic" "downtime_alerts" {
  name = "${var.app_name}-downtime-alerts"

  tags = {
    Name = "${var.app_name}-downtime-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.downtime_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}