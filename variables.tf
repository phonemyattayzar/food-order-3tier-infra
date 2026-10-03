# ==============================================================================
# Variables Definition
# ==============================================================================
# All configurable inputs for Networking, Security, Compute (ALB/ASG), and RDS.
# Defaults are aligned with AWS region ap-southeast-1 (Singapore).
# ==============================================================================

variable "aws_region" {
  description = "Target AWS region for deploying infrastructure"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project identifier used in resource naming and tags"
  type        = string
  default     = "food-order-3tier"
}

variable "environment" {
  description = "Deployment environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ------------------------------------------------------------------------------
# Networking (VPC & Subnets) Variables
# ------------------------------------------------------------------------------

variable "availability_zones" {
  description = "List of Availability Zones to deploy subnets across (requires at least 2)"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two Availability Zones are required for high availability."
  }
}

variable "vpc_cidr" {
  description = "Primary CIDR block for the Virtual Private Cloud (VPC)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the 2 public subnets (ALB & NAT Gateway)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly two public subnet CIDRs must be provided."
  }
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for the 2 private application subnets (EC2 Auto Scaling Group)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_app_subnet_cidrs) == 2
    error_message = "Exactly two private application subnet CIDRs must be provided."
  }
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for the 2 private database subnets (Multi-AZ RDS)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]

  validation {
    condition     = length(var.private_db_subnet_cidrs) == 2
    error_message = "Exactly two private database subnet CIDRs must be provided."
  }
}

# ------------------------------------------------------------------------------
# Compute Layer (ALB & EC2 ASG) Variables
# ------------------------------------------------------------------------------

variable "app_port" {
  description = "Port exposed by the backend application container running on EC2"
  type        = number
  default     = 8000
}

variable "health_check_path" {
  description = "HTTP path for ALB target group health checks"
  type        = string
  default     = "/api/v1"
}

variable "ec2_instance_type" {
  description = "EC2 instance type for the Auto Scaling Group worker nodes"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "ecr_repository_name" {
  description = "Custom name for the AWS ECR repository (leave blank to default to <project_name>-api)"
  type        = string
  default     = ""
}

variable "ecr_repository_url" {
  description = "Override ECR Repository URL if referencing an existing registry (leave blank to use auto-provisioned ECR)"
  type        = string
  default     = ""
}

variable "ecr_force_delete" {
  description = "If true, allows Terraform to destroy the ECR repository even if it contains images"
  type        = bool
  default     = true
}

variable "ecr_image_retention_days" {
  description = "Days before untagged images are automatically deleted from ECR"
  type        = number
  default     = 14
}

variable "ecr_max_image_count" {
  description = "Maximum number of tagged images to retain in ECR"
  type        = number
  default     = 30
}

variable "app_image_tag" {
  description = "Docker image tag to pull from ECR"
  type        = string
  default     = "latest"
}

# ------------------------------------------------------------------------------
# Database Layer (Multi-AZ RDS) Variables
# ------------------------------------------------------------------------------

variable "db_port" {
  description = "Port exposed by the database service (5432 for PostgreSQL, 3306 for MySQL)"
  type        = number
  default     = 5432
}

variable "db_engine" {
  description = "Database engine type (postgres or mysql)"
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "Database engine major/minor version"
  type        = string
  default     = "15.7"
}

variable "db_instance_class" {
  description = "RDS DB instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage size for RDS in Gigabytes"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum storage limit for auto-scaling storage in Gigabytes"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Default database schema name to initialize on creation"
  type        = string
  default     = "food_db"
}

variable "db_username" {
  description = "Master database administrator username"
  type        = string
  default     = "dbadmin"
}

variable "db_backup_retention_period" {
  description = "Automated backup retention period in days (1-35 days)"
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_period >= 1
    error_message = "Automated backup retention period must be at least 1 day for production databases."
  }
}

# ------------------------------------------------------------------------------
# Frontend Layer (S3 & CloudFront) Variables
# ------------------------------------------------------------------------------

variable "frontend_bucket_name" {
  description = "Explicit name for the frontend S3 bucket (leave empty to generate with unique suffix)"
  type        = string
  default     = ""
}

variable "frontend_force_destroy" {
  description = "Whether to allow destroying the frontend S3 bucket even if it contains objects"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront distribution price class (PriceClass_100, PriceClass_200, PriceClass_All)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Price class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "enable_alb_api_routing" {
  description = "Whether CloudFront should route /api/* and /static/* traffic directly to the Application Load Balancer"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Backend Security & Authentication Variables (SSM Parameter Store)
# ------------------------------------------------------------------------------

variable "secret_key" {
  description = "Backend JWT Secret Key (leave empty to generate automatically via random_password)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "jwt_algorithm" {
  description = "Backend JWT signing algorithm"
  type        = string
  default     = "HS256"
}

variable "jwt_access_token_expire_minutes" {
  description = "Backend JWT access token expiration duration in minutes"
  type        = number
  default     = 11520
}

