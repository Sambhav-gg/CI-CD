# ── SSM: active slot tracking (blue | green) ─────────────────────────────────
resource "aws_ssm_parameter" "active_slot" {
  name  = "/myapp/deploy/active-slot"
  type  = "String"
  value = "blue"           # starts on blue; Jenkins flips this after each cutover

  lifecycle {
    ignore_changes = [value]   # Terraform sets initial value only; pipeline owns this
  }
}

# ── SSM: current image tag (unchanged from rolling deploy) ───────────────────
resource "aws_ssm_parameter" "image_tag" {
  name  = "/myapp/deploy/image-tag"
  type  = "String"
  value = "latest"

  lifecycle {
    ignore_changes = [value]
  }
}

# ── SSM: ALB listener ARN (needed by pipeline for cutover command) ────────────
resource "aws_ssm_parameter" "listener_arn" {
  name  = "/myapp/infra/listener-arn"
  type  = "String"
  value = aws_lb_listener.app.arn
}

resource "aws_ssm_parameter" "test_listener_arn" {
  name  = "/myapp/infra/test-listener-arn"
  type  = "String"
  value = aws_lb_listener.test.arn
}

# ── SSM: target group ARNs ────────────────────────────────────────────────────
resource "aws_ssm_parameter" "blue_tg_arn" {
  name  = "/myapp/infra/tg-blue-arn"
  type  = "String"
  value = aws_lb_target_group.blue.arn
}

resource "aws_ssm_parameter" "green_tg_arn" {
  name  = "/myapp/infra/tg-green-arn"
  type  = "String"
  value = aws_lb_target_group.green.arn
}
