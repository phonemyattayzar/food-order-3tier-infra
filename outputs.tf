# ==============================================================================
# Outputs Definition
# ==============================================================================
# Exposes essential networking, compute, security, and database attributes.
# ==============================================================================

# ------------------------------------------------------------------------------
# VPC & Subnet Outputs
# ------------------------------------------------------------------------------

output "aws_region" {
  description = "AWS deployment region"
  value       = var.aws_region
}

output "vpc_id" {
  description = "The ID of the primary VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "The CIDR block allocated to the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs for the 2 public subnets across availability zones"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "List of IDs for the 2 private application subnets across availability zones"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "List of IDs for the 2 private database subnets across availability zones"
  value       = aws_subnet.private_db[*].id
}

output "db_subnet_group_name" {
  description = "Name of the RDS DB Subnet Group created from private DB subnets"
  value       = aws_db_subnet_group.this.name
}

# ------------------------------------------------------------------------------
# Gateway & Elastic IP Outputs
# ------------------------------------------------------------------------------

output "nat_gateway_id" {
  description = "ID of the NAT Gateway deployed in public subnet 0"
  value       = aws_nat_gateway.this.id
}

output "nat_gateway_public_ip" {
  description = "Public Elastic IP assigned to the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

# ------------------------------------------------------------------------------
# Chained Security Group Outputs
# ------------------------------------------------------------------------------

output "alb_security_group_id" {
  description = "Security Group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Security Group ID for the EC2 Auto Scaling Group application instances"
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Security Group ID for the Multi-AZ RDS database instance"
  value       = aws_security_group.db.id
}

# ------------------------------------------------------------------------------
# ALB Outputs
# ------------------------------------------------------------------------------

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer (entry point for web traffic)"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.this.arn
}

output "target_group_arn" {
  description = "ARN of the ALB Target Group"
  value       = aws_lb_target_group.this.arn
}

# ------------------------------------------------------------------------------
# EC2 Auto Scaling Group Outputs
# ------------------------------------------------------------------------------

output "asg_name" {
  description = "Name of the EC2 Auto Scaling Group"
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "ARN of the EC2 Auto Scaling Group"
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "ID of the EC2 Launch Template"
  value       = aws_launch_template.this.id
}

output "ec2_iam_role_arn" {
  description = "ARN of the EC2 IAM Role used for SSM and ECR access"
  value       = aws_iam_role.ec2_role.arn
}

# ------------------------------------------------------------------------------
# RDS Multi-AZ Database Outputs
# ------------------------------------------------------------------------------

output "rds_endpoint" {
  description = "Connection endpoint for the RDS database instance (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "rds_address" {
  description = "Hostname of the RDS database instance"
  value       = aws_db_instance.this.address
}

output "rds_port" {
  description = "Port the database service is listening on"
  value       = aws_db_instance.this.port
}

output "rds_db_name" {
  description = "Default database schema name"
  value       = aws_db_instance.this.db_name
}

output "rds_secret_arn" {
  description = "ARN of the Secrets Manager secret storing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

# ------------------------------------------------------------------------------
# Container Registry Outputs (AWS ECR)
# ------------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "URL of the Amazon ECR repository for application container images"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the Amazon ECR repository"
  value       = aws_ecr_repository.app.arn
}

output "ecr_repository_name" {
  description = "Name of the Amazon ECR repository"
  value       = aws_ecr_repository.app.name
}

# ------------------------------------------------------------------------------
# Frontend & CDN Outputs (CloudFront + S3)
# ------------------------------------------------------------------------------

output "frontend_bucket_name" {
  description = "Name of the S3 bucket hosting the React frontend"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "ARN of the S3 bucket hosting the React frontend"
  value       = aws_s3_bucket.frontend.arn
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution (used for cache invalidations in CI/CD)"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.arn
}

output "cloudfront_domain_name" {
  description = "Public domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_url" {
  description = "Primary HTTPS URL to access the deployed React frontend application"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

# ------------------------------------------------------------------------------
# Systems Manager (SSM) Parameter Store Outputs
# ------------------------------------------------------------------------------

output "ssm_parameter_prefix" {
  description = "Base prefix for application parameters in AWS SSM Parameter Store"
  value       = "/${var.project_name}/${var.environment}"
}

output "ssm_database_url_name" {
  description = "Name of the SSM parameter storing the database connection URL"
  value       = aws_ssm_parameter.database_url.name
}

output "ssm_database_url_arn" {
  description = "ARN of the SSM parameter storing the database connection URL"
  value       = aws_ssm_parameter.database_url.arn
}

output "ssm_secret_key_name" {
  description = "Name of the SSM parameter storing the JWT secret key"
  value       = aws_ssm_parameter.secret_key.name
}

output "ssm_secret_key_arn" {
  description = "ARN of the SSM parameter storing the JWT secret key"
  value       = aws_ssm_parameter.secret_key.arn
}

