# ==============================================================================
# Frontend Static Hosting (CloudFront CDN + S3 + Origin Access Control)
# ==============================================================================
# Architecture Standard:
# - Zero Public S3 Buckets: All public access blocked. Bucket is only accessible
#   via AWS CloudFront using Origin Access Control (OAC) with SigV4 signing.
# - High Performance CDN: Cached globally via CloudFront Edge locations.
# - Single-Page Application (SPA) Routing: Custom error responses route 403/404
#   to index.html so React client-side routing works seamlessly.
# - Unified Origin Routing: CloudFront routes static SPA traffic to S3 and
#   dynamically routes /api/* and /static/* to the Application Load Balancer,
#   avoiding CORS and Mixed Content issues.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Random Suffix for Globally Unique S3 Bucket Naming
# ------------------------------------------------------------------------------
resource "random_id" "frontend_bucket_suffix" {
  byte_length = 4
}

# ------------------------------------------------------------------------------
# 2. S3 Bucket for React Frontend Static Assets
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket        = var.frontend_bucket_name != "" ? var.frontend_bucket_name : "${var.project_name}-${var.environment}-frontend-${random_id.frontend_bucket_suffix.hex}"
  force_destroy = var.frontend_force_destroy

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-bucket"
    Tier = "Frontend-S3"
  }
}

# Enforce bucket owner for all uploaded objects (disables legacy ACLs)
resource "aws_s3_bucket_ownership_controls" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block all public read/write access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable Server-Side Encryption with Amazon S3 managed keys (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable versioning for rollback capabilities and asset integrity
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------------------------------------------------------------
# 3. CloudFront Origin Access Control (OAC)
# ------------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-${var.environment}-frontend-oac"
  description                       = "OAC for CloudFront to securely access S3 frontend bucket via SigV4"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ------------------------------------------------------------------------------
# 4. Managed CloudFront Cache & Origin Request Policies
# ------------------------------------------------------------------------------
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ------------------------------------------------------------------------------
# 5. CloudFront Distribution
# ------------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-${var.environment}-frontend"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class

  # S3 Origin for React static build files
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Optional ALB Origin for backend API and static uploads routing
  dynamic "origin" {
    for_each = var.enable_alb_api_routing ? [1] : []
    content {
      domain_name = aws_lb.this.dns_name
      origin_id   = "ALB-${aws_lb.this.name}"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "http-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Default Cache Behavior: Serves React SPA static files from S3
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # Ordered Cache Behavior 1: Routes /api/* directly to the backend ALB
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_alb_api_routing ? [1] : []
    content {
      path_pattern     = "/api/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "ALB-${aws_lb.this.name}"

      cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id

      viewer_protocol_policy = "redirect-to-https"
    }
  }

  # Ordered Cache Behavior 2: Routes /static/* (uploads) directly to the backend ALB
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_alb_api_routing ? [1] : []
    content {
      path_pattern     = "/static/*"
      allowed_methods  = ["GET", "HEAD", "OPTIONS"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "ALB-${aws_lb.this.name}"

      cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id

      viewer_protocol_policy = "redirect-to-https"
    }
  }

  # SPA Custom Error Response: Route 403/404 to /index.html for client-side routing
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-cf"
    Tier = "Frontend-CDN"
  }
}

# ------------------------------------------------------------------------------
# 6. S3 Bucket Policy for CloudFront Origin Access Control (OAC)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}
