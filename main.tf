# ==============================================================================
# AWS Provider & Remote State Backend Configuration
# ==============================================================================
# Architecture Standard:
# - Enforces minimum Terraform and AWS provider versions for syntax stability.
# - Stores state remotely in an S3 bucket with server-side encryption enabled.
# - Leverages native S3 state locking (use_lockfile) to prevent race conditions without DynamoDB.
# - Injects standard organizational tags across all provisioned AWS resources.
# ==============================================================================

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # ----------------------------------------------------------------------------
  # Remote State Backend (S3 with Native State Locking)
  # ----------------------------------------------------------------------------
  # Note: The S3 bucket must be created prior to initializing this backend.
  # Terraform 1.10+ uses native S3 conditional writes for state locking,
  # eliminating the need for a separate DynamoDB table.
  # You can supply backend values via a backend config file or CLI:
  # terraform init -backend-config="bucket=<your-bucket>" ...
  # ----------------------------------------------------------------------------
  backend "s3" {
    bucket       = "food-order-tfstate-051131628511-ap-southeast-1"
    key          = "networking/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

# ------------------------------------------------------------------------------
# Primary AWS Provider Configuration
# ------------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Tier        = "Networking"
    }
  }
}

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
