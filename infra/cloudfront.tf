# CloudFront Distribution for S3 Content

# Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "content" {
  name                              = "${var.project_name}-s3-oac"
  description                       = "OAC for Ghost S3 content bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "content" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Ghost content CDN"
  default_root_object = ""
  price_class         = "PriceClass_100" # Use only North America and Europe (cheapest)

  origin {
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_id                = "S3-${var.project_name}-content"
    origin_access_control_id = aws_cloudfront_origin_access_control.content.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.project_name}-content"

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400    # 1 day
    max_ttl                = 31536000 # 1 year
    compress               = true
  }

  # Cache behavior for images (long cache)
  ordered_cache_behavior {
    path_pattern     = "content/images/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${var.project_name}-content"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 86400     # 1 day
    default_ttl            = 604800    # 1 week
    max_ttl                = 31536000  # 1 year
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # For custom domain, uncomment and configure ACM certificate:
    # acm_certificate_arn      = aws_acm_certificate.cdn.arn
    # ssl_support_method       = "sni-only"
    # minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${var.project_name}-cdn"
  }
}

# Optional: ACM Certificate for custom CDN domain
# Uncomment if you want a custom domain for CDN (e.g., cdn.your-domain.com)
# 
# resource "aws_acm_certificate" "cdn" {
#   provider          = aws.us_east_1  # CloudFront requires us-east-1
#   domain_name       = "cdn.${var.domain_name}"
#   validation_method = "DNS"
#
#   lifecycle {
#     create_before_destroy = true
#   }
#
#   tags = {
#     Name = "${var.project_name}-cdn-cert"
#   }
# }
