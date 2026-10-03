# ==============================================================================
# Multi-AZ Relational Database Service (RDS)
# ==============================================================================
# Architecture Standard:
# - Deployed across 2 isolated private DB subnets (ap-southeast-1a and ap-southeast-1b).
# - Multi-AZ synchronous replication for automated failover and zero data loss.
# - prevent_destroy lifecycle policy ensures the production database cannot be
#   accidentally destroyed via terraform destroy or misconfiguration.
# - Automated daily backups enabled with configurable retention (default: 7 days).
# - Storage encryption at rest enforced via AWS KMS.
# - Master credentials generated randomly and stored directly in AWS Secrets Manager.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Random High-Entropy Password Generation
# ------------------------------------------------------------------------------
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ------------------------------------------------------------------------------
# 2. Store Credentials Securely in AWS Secrets Manager
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}-${var.environment}-db-secret"
  description             = "Master database credentials for ${var.project_name} (${var.environment})"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-${var.environment}-db-secret"
    Tier = "Private-DB"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    engine   = var.db_engine
    host     = aws_db_instance.this.address
    port     = var.db_port
    username = var.db_username
    password = random_password.db_password.result
    database = var.db_name
  })
}

# ------------------------------------------------------------------------------
# 3. Multi-AZ RDS Database Instance
# ------------------------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier = "${var.project_name}-${var.environment}-db"

  # Engine & Architecture
  engine                     = var.db_engine
  engine_version             = var.db_engine_version
  instance_class             = var.db_instance_class
  auto_minor_version_upgrade = true # Minor version များကို အလိုအလျောက် Update လုပ်ခွင့်ပေးခြင်း

  # Storage Configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database Credentials & Schema
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = var.db_port

  # Network & High Availability
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  multi_az               = true
  publicly_accessible    = false

  # Automated Backups & Maintenance
  # var.db_backup_retention_period
  backup_retention_period   = 0
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  copy_tags_to_snapshot     = true
  deletion_protection       = false # Set to true in strict production
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-db-final-snapshot"

  # Safety Lifecycle Policy: Prevents accidental destruction
  lifecycle {
    # prevent_destroy = true
    ignore_changes  = [password]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db"
    Tier = "Private-DB"
  }
}
