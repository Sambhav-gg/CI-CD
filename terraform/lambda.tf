data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/uptime-monitor.js"
  output_path = "${path.module}/../lambda/uptime-monitor.zip"
}

resource "aws_lambda_function" "uptime_monitor" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "${var.app_name}-uptime-monitor"
  role             = aws_iam_role.lambda.arn
  handler          = "uptime-monitor.handler"
  runtime          = "nodejs18.x"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      ALB_DNS       = aws_lb.app.dns_name
      SNS_TOPIC_ARN = aws_sns_topic.downtime_alerts.arn
      AWS_REGION_ID = var.aws_region
    }
  }

  tags = {
    Name = "${var.app_name}-uptime-monitor"
  }
}

resource "aws_cloudwatch_event_rule" "ping" {
  name                = "${var.app_name}-ping-every-5-mins"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name = "${var.app_name}-ping-rule"
  }
}

resource "aws_cloudwatch_event_target" "ping" {
  rule      = aws_cloudwatch_event_rule.ping.name
  target_id = "UptimeMonitorLambda"
  arn       = aws_lambda_function.uptime_monitor.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.uptime_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ping.arn
}