# outputs will be uncommented as we add each resource

 output "jenkins_public_ip" {
   value       = aws_instance.jenkins.public_ip
   description = "Jenkins EC2 public IP"
 }

 output "app_private_ip" {
   value       = aws_instance.app.private_ip
   description = "App EC2 private IP"
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