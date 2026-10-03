# ==============================================================================
# Application Load Balancer (ALB) & Target Group
# ==============================================================================
# Architecture Standard:
# - Internet-facing ALB deployed across the 2 public subnets (ap-southeast-1a/b).
# - Target Group routes traffic to EC2 Auto Scaling Group instances on app_port.
# - Health check validated against backend API endpoint (/api/v1) with strict
#   healthy/unhealthy thresholds to ensure only responsive instances receive traffic.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Application Load Balancer
# ------------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
    Tier = "Public-ALB"
  }
}

# ------------------------------------------------------------------------------
# 2. ALB Target Group with Health Check
# ------------------------------------------------------------------------------
resource "aws_lb_target_group" "this" {
  name                 = "${var.project_name}-${var.environment}-tg"
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = aws_vpc.this.id
  target_type          = "instance"
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
    Tier = "Public-ALB"
  }
}

# ------------------------------------------------------------------------------
# 3. ALB HTTP Listener
# ------------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
