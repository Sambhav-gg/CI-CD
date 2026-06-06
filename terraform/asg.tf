resource "aws_launch_template" "app" {
  name_prefix   = "${var.app_name}-lt-"
  image_id      = var.ami_id
  instance_type = var.app_instance_type
  key_name      = var.key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  user_data = base64encode(local.app_userdata)

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 8
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.app_name}-asg-instance"
    }
  }
}

# ── BLUE ASG (initial LIVE slot) ─────────────────────────────────────────────
resource "aws_autoscaling_group" "blue" {
  name                = "${var.app_name}-asg-blue"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 3
  vpc_zone_identifier = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  target_group_arns   = [aws_lb_target_group.blue.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.app_name}-blue"
    propagate_at_launch = true
  }

  tag {
    key                 = "Slot"
    value               = "blue"
    propagate_at_launch = true
  }
}

# ── GREEN ASG (initial IDLE slot — new code lands here first) ─────────────────
resource "aws_autoscaling_group" "green" {
  name                = "${var.app_name}-asg-green"
  desired_capacity    = 0     # starts at 0; Jenkins scales it up during deploy
  min_size            = 0
  max_size            = 3
  vpc_zone_identifier = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  target_group_arns   = [aws_lb_target_group.green.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.app_name}-green"
    propagate_at_launch = true
  }

  tag {
    key                 = "Slot"
    value               = "green"
    propagate_at_launch = true
  }

  lifecycle {
    # Jenkins manages desired_capacity during deployments.
    ignore_changes = [desired_capacity]
  }
}

# ── Scale-out / scale-in policies (shared, wired to active slot in pipeline) ──
resource "aws_autoscaling_policy" "blue_scale_out" {
  name                   = "${var.app_name}-blue-scale-out"
  autoscaling_group_name = aws_autoscaling_group.blue.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_autoscaling_policy" "blue_scale_in" {
  name                   = "${var.app_name}-blue-scale-in"
  autoscaling_group_name = aws_autoscaling_group.blue.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "green_scale_out" {
  name                   = "${var.app_name}-green-scale-out"
  autoscaling_group_name = aws_autoscaling_group.green.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_autoscaling_policy" "green_scale_in" {
  name                   = "${var.app_name}-green-scale-in"
  autoscaling_group_name = aws_autoscaling_group.green.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}
