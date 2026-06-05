resource "aws_ssm_parameter" "image_tag" {
  name  = "/myapp/deploy/image-tag"
  type  = "String"
  value = "latest"

  lifecycle {
    ignore_changes = [value]
  }
}
