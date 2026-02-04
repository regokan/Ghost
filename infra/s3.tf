# S3 Bucket for Ghost Content

resource "aws_s3_bucket" "content" {
  bucket = var.s3_bucket_name

  tags = {
    Name = "${var.project_name}-content"
  }
}

# Ownership controls: allow ACLs (required by S3 storage adapter), but keep bucket private via policies
resource "aws_s3_bucket_ownership_controls" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    # Allows ACLs while keeping bucket-owner preferred; avoids BucketOwnerEnforced (which disables ACLs entirely)
    object_ownership = "BucketOwnerPreferred"
  }
}

# Block public access (CloudFront will serve content)
resource "aws_s3_bucket_public_access_block" "content" {
  bucket = aws_s3_bucket.content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning for content protection
resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle rules for old versions
resource "aws_s3_bucket_lifecycle_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# CORS configuration for Ghost uploads
resource "aws_s3_bucket_cors_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://${var.domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Bucket policy for CloudFront OAC (must exist after distribution so ARN is valid)
resource "aws_s3_bucket_policy" "content" {
  bucket = aws_s3_bucket.content.id

  depends_on = [aws_cloudfront_distribution.content]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.content.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.content.arn
          }
        }
      }
    ]
  })
}
