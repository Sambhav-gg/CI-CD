resource "aws_iam_policy" "jenkins_ssm_asg" {
  name        = "${var.app_name}-jenkins-ssm-asg-policy"
  description = "Allows Jenkins to update deployment image tags in SSM and trigger ASG instance refreshes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ssm:PutParameter",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/myapp/deploy/image-tag"
      },
      {
        Effect   = "Allow"
        Action   = [
          "autoscaling:StartInstanceRefresh",
          "autoscaling:DescribeInstanceRefreshes",
          "autoscaling:CancelInstanceRefresh"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm_asg" {
  role       = aws_iam_role.jenkins.name
  policy_arn = aws_iam_policy.jenkins_ssm_asg.arn
}

resource "aws_iam_policy" "app_ssm" {
  name        = "${var.app_name}-app-ssm-policy"
  description = "Allows App instances to read the current deployment tag from SSM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/myapp/deploy/image-tag"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app_ssm.arn
}
