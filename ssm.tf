# ==============================================================================
# AWS Systems Manager (SSM) Parameter Store Configuration
# ==============================================================================
# Architecture Standard:
# - Securely stores database connection parameters, master credentials, and JWT secrets.
# - Sensitive credentials use SecureString (encrypted with default KMS key alias/aws/ssm).
# - Non-sensitive configuration uses String.
# - Hierarchical naming standard: /<project_name>/<environment>/<PARAMETER_NAME>
# - Allows EC2 Launch Template user data to inject environment variables into containers.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Random High-Entropy JWT Secret Key (if not explicitly provided)
# ------------------------------------------------------------------------------
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

locals {
  app_secret_key = var.secret_key != "" ? var.secret_key : random_password.secret_key.result
  database_url   = "postgresql+psycopg2://${var.db_username}:${urlencode(random_password.db_password.result)}@${aws_db_instance.this.address}:${var.db_port}/${var.db_name}"
}

# ------------------------------------------------------------------------------
# 2. SSM Parameters for Backend Application
# ------------------------------------------------------------------------------

# Database Connection URL (SecureString)
resource "aws_ssm_parameter" "database_url" {
  name        = "/${var.project_name}/${var.environment}/DATABASE_URL"
  description = "Full PostgreSQL connection URL for backend service"
  type        = "SecureString"
  value       = local.database_url

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-database-url"
    Tier = "Backend-Config"
  }
}

# PostgreSQL Master Username (String)
resource "aws_ssm_parameter" "postgres_user" {
  name        = "/${var.project_name}/${var.environment}/POSTGRES_USER"
  description = "PostgreSQL master username"
  type        = "String"
  value       = var.db_username

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-postgres-user"
    Tier = "Backend-Config"
  }
}

# PostgreSQL Master Password (SecureString)
resource "aws_ssm_parameter" "postgres_password" {
  name        = "/${var.project_name}/${var.environment}/POSTGRES_PASSWORD"
  description = "PostgreSQL master password"
  type        = "SecureString"
  value       = random_password.db_password.result

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-postgres-password"
    Tier = "Backend-Config"
  }
}

# PostgreSQL Database Name (String)
resource "aws_ssm_parameter" "postgres_db" {
  name        = "/${var.project_name}/${var.environment}/POSTGRES_DB"
  description = "PostgreSQL database name"
  type        = "String"
  value       = var.db_name

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-postgres-db"
    Tier = "Backend-Config"
  }
}

# PostgreSQL Host Address (String)
resource "aws_ssm_parameter" "postgres_host" {
  name        = "/${var.project_name}/${var.environment}/POSTGRES_HOST"
  description = "PostgreSQL host endpoint address"
  type        = "String"
  value       = aws_db_instance.this.address

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-postgres-host"
    Tier = "Backend-Config"
  }
}

# PostgreSQL Port (String)
resource "aws_ssm_parameter" "postgres_port" {
  name        = "/${var.project_name}/${var.environment}/POSTGRES_PORT"
  description = "PostgreSQL port"
  type        = "String"
  value       = tostring(var.db_port)

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-postgres-port"
    Tier = "Backend-Config"
  }
}

# Backend Secret Key for JWT Authentication (SecureString)
resource "aws_ssm_parameter" "secret_key" {
  name        = "/${var.project_name}/${var.environment}/SECRET_KEY"
  description = "Backend JWT secret key for signing authentication tokens"
  type        = "SecureString"
  value       = local.app_secret_key

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-secret-key"
    Tier = "Backend-Config"
  }
}

# JWT Algorithm (String)
resource "aws_ssm_parameter" "algorithm" {
  name        = "/${var.project_name}/${var.environment}/ALGORITHM"
  description = "Backend JWT signing algorithm"
  type        = "String"
  value       = var.jwt_algorithm

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-algorithm"
    Tier = "Backend-Config"
  }
}

# JWT Access Token Expiration (String)
resource "aws_ssm_parameter" "access_token_expire_minutes" {
  name        = "/${var.project_name}/${var.environment}/ACCESS_TOKEN_EXPIRE_MINUTES"
  description = "Backend JWT access token expiration duration in minutes"
  type        = "String"
  value       = tostring(var.jwt_access_token_expire_minutes)

  tags = {
    Name = "${var.project_name}-${var.environment}-ssm-access-token-expire-minutes"
    Tier = "Backend-Config"
  }
}
