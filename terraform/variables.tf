variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type        = string
  description = "Name prefix for all resources."
  default     = "my-react-app"
}

# The only value Terraform actually needs from you. It is a security boundary — it
# decides which GitHub repository may assume the deploy role — so it is never guessed
# or defaulted. GitHub puts this id-qualified form in the OIDC subject claim; the plain
# owner/repo name is not used, because a name can be freed and re-registered by someone
# else while numeric ids are never reissued. Get it from:
#   gh api repos/<owner>/<repo> --jq '"\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'
variable "github_repo_ids" {
  type        = string
  description = "owner@owner_id/repo@repo_id, e.g. maheswarareddyuma@118102588/claude-react-app@1315707959. Scopes the OIDC trust policy."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+@[0-9]+/[A-Za-z0-9._-]+@[0-9]+$", var.github_repo_ids))
    error_message = "Must be owner@owner_id/repo@repo_id — both numeric ids required."
  }
}
