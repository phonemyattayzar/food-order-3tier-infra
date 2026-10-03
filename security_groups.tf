# ==============================================================================
# Chained Security Groups (ALB SG -> EC2 App SG -> RDS DB SG)
# ==============================================================================
# Architecture Standard:
# - Zero Trust / Least Privilege: No tier is exposed beyond what is strictly necessary.
# - Chained references using `source_security_group_id` prevent unauthorized traffic,
#   even from other instances within the same VPC.
# - Standalone `aws_security_group_rule` resources are used to eliminate circular
#   dependency deadlocks during Terraform DAG resolution.
# - Zero SSH exposure: Port 22 is intentionally omitted. Operators access EC2
#   instances securely using AWS Systems Manager (SSM) Session Manager.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Tier 1: Application Load Balancer Security Group
# ------------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Controls public inbound traffic to the Application Load Balancer"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
    Tier = "Public-ALB"
  }
}

# ALB Ingress: HTTP (Port 80) from anywhere
resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  description       = "Allow inbound HTTP traffic from the public internet"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# ALB Ingress: HTTPS (Port 443) from anywhere
resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  description       = "Allow inbound HTTPS traffic from the public internet"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

# ALB Egress: Forward traffic ONLY to EC2 Application Security Group
resource "aws_security_group_rule" "alb_egress_app" {
  type                     = "egress"
  description              = "Allow outbound traffic only to backend application instances"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.alb.id
}

# ------------------------------------------------------------------------------
# 2. Tier 2: EC2 Application Security Group (Auto Scaling Group)
# ------------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-sg"
  description = "Restricts EC2 application traffic strictly to ALB ingress"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-app-sg"
    Tier = "Private-App"
  }
}

# EC2 App Ingress: Allow traffic on app_port ONLY from the ALB Security Group
resource "aws_security_group_rule" "app_ingress_from_alb" {
  type                     = "ingress"
  description              = "Allow application traffic exclusively from the ALB"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.app.id
}

# EC2 App Egress: Outbound access for NAT Gateway (ECR image pull, SSM Session Manager, OS updates)
resource "aws_security_group_rule" "app_egress_all" {
  type              = "egress"
  description       = "Allow outbound egress via NAT Gateway for ECR, SSM, and package management"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
}

# ------------------------------------------------------------------------------
# 3. Tier 3: RDS Database Security Group (PostgreSQL/MySQL)
# ------------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.environment}-db-sg"
  description = "Restricts database access strictly to the EC2 application tier"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sg"
    Tier = "Private-DB"
  }
}

# RDS DB Ingress: Allow DB port traffic ONLY from the EC2 App Security Group
resource "aws_security_group_rule" "db_ingress_from_app" {
  type                     = "ingress"
  description              = "Allow database connections exclusively from EC2 application tier"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.db.id
}

# RDS DB Egress: Denied / No outbound access needed (RDS responds via stateful return traffic)
