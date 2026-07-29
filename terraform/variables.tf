variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type        = string
  description = "Name prefix for all resources."
  default     = "my-react-app"
}

# The only value Terraform actually needs from you. It is a security boundary —
# it decides which GitHub repository is allowed to assume the deploy role — so it
# is never guessed or defaulted.
variable "github_repo" {
  type        = string
  description = "owner/repo, e.g. maheswarareddyuma/claude-react-app. Scopes the OIDC trust policy."

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "Must be owner/repo — no https://, no github.com/, no .git suffix."
  }
}
