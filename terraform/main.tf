# Account id comes from your credentials — nothing to configure.
data "aws_caller_identity" "current" {}

# S3 bucket names are globally unique across all of AWS. Suffixing the account id
# makes that automatic, so this is not a question anyone has to answer. The bucket
# is private behind CloudFront, so its name is never user-visible anyway.
resource "aws_s3_bucket" "site" {
  bucket = "${var.project}-site-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Versioning keeps every superseded copy of every asset forever. Each deploy replaces
# index.html and leaves the old one noncurrent, so the bill grows with deploy count
# rather than site size. 30 days is well past any window in which a rollback is still
# the tool you would reach for.
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  # Versioning must exist before a noncurrent-version rule can reference it.
  depends_on = [aws_s3_bucket_versioning.site]

  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    # Empty filter = every object in the bucket.
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  default_root_object = "index.html"
  comment             = var.project

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.site.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-${aws_s3_bucket.site.id}"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  # SPA: client-side routes are not real S3 keys.
  dynamic "custom_error_response" {
    for_each = [403, 404]
    content {
      error_code         = custom_error_response.value
      response_code      = 200
      response_page_path = "/index.html"
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Default *.cloudfront.net cert. For a custom domain: add `aliases`, create an
  # aws_acm_certificate with `region = "us-east-1"` (provider v6 takes region
  # per-resource — no provider alias needed), then swap this for:
  #   acm_certificate_arn = ...
  #   ssl_support_method  = "sni-only"
  #   minimum_protocol_version = "TLSv1.2_2021"
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  price_class = "PriceClass_100"
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json
}
