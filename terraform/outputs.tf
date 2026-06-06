# outputs will be uncommented as we add each resource

 output "jenkins_public_ip" {
   value       = aws_instance.jenkins.public_ip
   description = "Jenkins EC2 public IP"
 }


 output "alb_dns" {
   value       = aws_lb.app.dns_name
   description = "ALB DNS — use this in Jenkinsfile and Lambda"
 }

 output "ecr_repository_url" {
   value       = aws_ecr_repository.app.repository_url
   description = "ECR URI — use this in Jenkinsfile"
 }

 output "sns_topic_arn" {
   value       = aws_sns_topic.downtime_alerts.arn
   description = "SNS topic ARN — use this in Lambda"
 }
# ── Blue-green additions ───────────────────────────────────────────────────────
output "blue_asg_name" {
  description = "Blue ASG name"
  value       = aws_autoscaling_group.blue.name
}

output "green_asg_name" {
  description = "Green ASG name"
  value       = aws_autoscaling_group.green.name
}

output "blue_tg_arn" {
  description = "Blue target group ARN"
  value       = aws_lb_target_group.blue.arn
}

output "green_tg_arn" {
  description = "Green target group ARN"
  value       = aws_lb_target_group.green.arn
}

output "test_listener_arn" {
  description = "Port 8080 test listener ARN"
  value       = aws_lb_listener.test.arn
}
