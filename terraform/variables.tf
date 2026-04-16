variable "aws_region" {
  default = "eu-north-1"
}

variable "app_name" {
  default = "my-app"
}

variable "alert_email" {
  description = "Email for downtime alerts"
  type        = string
}

variable "key_pair_name" {
  description = "AWS key pair name for EC2 SSH access"
  type        = string
}

variable "your_ip" {
  description = "Your local IP for SSH access to Jenkins"
  type        = string
}

variable "jenkins_instance_type" {
  default = "c7i-flex.large"
}

variable "app_instance_type" {
  default = "t3.micro"
}

variable "ami_id" {
  description = "Ubuntu 22.04 AMI for eu-north-1"
  default     = "ami-089146c5626baa6bf"
}