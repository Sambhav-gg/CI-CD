resource "aws_lb" "app" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name = "${var.app_name}-alb"
  }
}

# ── Blue Target Group (initially LIVE) ───────────────────────────────────────
resource "aws_lb_target_group" "blue" {
  name     = "${var.app_name}-tg-blue"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = { Name = "${var.app_name}-tg-blue", Slot = "blue" }
}

# ── Green Target Group (initially IDLE / new deploys land here) ──────────────
resource "aws_lb_target_group" "green" {
  name     = "${var.app_name}-tg-green"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = { Name = "${var.app_name}-tg-green", Slot = "green" }
}

# ── Production Listener (port 80) — forwards to ACTIVE slot via SSM ──────────
# The active target group is controlled by the Jenkinsfile (SSM param /myapp/deploy/active-slot).
# Terraform manages the listener; Jenkins does the cutover via aws elbv2 modify-listener.
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  # Default: point to blue on first apply.
  # After first deploy this is managed by the pipeline, not Terraform.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  lifecycle {
    # Prevent Terraform from resetting the listener target group back to blue
    # after Jenkins has switched it to green.
    ignore_changes = [default_action]
  }
}

# ── Test Listener (port 8080) — always points to IDLE (green/blue) slot ──────
# Lets you smoke-test the new version before cutover.
resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.app.arn
  port              = 8080
  protocol          = "HTTP"

  # Default: point to green on first apply (green = idle slot initially).
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}
