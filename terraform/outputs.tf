output "site_url" {
  value = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "bucket_name" {
  value = aws_s3_bucket.site.id
}

output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "ci_role_arn" {
  description = "Put this in the repo secret AWS_DEPLOY_ROLE_ARN."
  value       = aws_iam_role.ci.arn
}
