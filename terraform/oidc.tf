# If the account already has the GitHub OIDC provider, do NOT create a second one —
# `terraform import aws_iam_openid_connect_provider.github <arn>` instead.
#
# No thumbprint_list: per the provider docs, AWS validates GitHub's OIDC endpoint
# against its own trusted root CAs and ignores any thumbprint you configure. A
# pinned thumbprint here is dead config that silently rots when GitHub rotates.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # main only. PR jobs build and test but never assume this role, so a PR from
    # a fork cannot reach the bucket. Do not loosen this to `repo:...:*`.
    #
    # Id-qualified subject only (`owner@<owner_id>/repo@<repo_id>`) — that is the form
    # GitHub issues for this repo, confirmed in CloudTrail. The name-based form is
    # deliberately absent: it binds to a string that becomes claimable by a stranger if
    # the repo or the account is ever renamed or deleted. Numeric ids are never reissued.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo_ids}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.project}-github-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_trust.json
}

# CI only uploads build output. It cannot touch Terraform state, IAM, or the
# distribution config — infra changes are applied locally by a human.
data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "ListSiteBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }

  # No s3:GetObject — `aws s3 sync` compares against the ListBucket result, so the
  # deploy never reads object bodies. Upload and delete is the whole job.
  statement {
    sid       = "SyncSiteObjects"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  statement {
    sid       = "InvalidateOnly"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "${var.project}-ci"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}
