# ==============================================================================
# AWS ECR (Elastic Container Registry) Configuration
# ==============================================================================
# Architecture Standard:
# - Dedicated private container registry for backend application Docker images.
# - Image vulnerability scan-on-push enabled for continuous security compliance.
# - Tag mutability set to MUTABLE for rolling latest/semantic version releases.
# - KMS / AES-256 server-side encryption enabled at rest.
# - Lifecycle policies automatically purge untagged images and retain only recent
#   tagged production images to prevent unnecessary storage costs.
# ==============================================================================

locals {
  ecr_name = var.ecr_repository_name != "" ? var.ecr_repository_name : "${var.project_name}-api"
}

# ------------------------------------------------------------------------------
# 1. Private ECR Repository
# ------------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = local.ecr_name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = local.ecr_name
    Tier = "Container-Registry"
  }
}

# ------------------------------------------------------------------------------
# 2. ECR Lifecycle Policy (Automated Image Cleanup)
# ------------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than ${var.ecr_image_retention_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.ecr_image_retention_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Retain only the last ${var.ecr_max_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "latest", "prod"]
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
