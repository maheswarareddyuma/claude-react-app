terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.57"
    }
  }

  # ponytail: local state — single operator, no state bucket yet. Uncomment for S3 remote
  # state (partial config; supply bucket+region via -backend-config) when a second person
  # or CI needs to run terraform. use_lockfile = S3-native locking, no DynamoDB (TF >= 1.10).
  # backend "s3" {
  #   key          = "react-app/terraform.tfstate"
  #   use_lockfile = true
  #   encrypt      = true
  # }
}

provider "aws" {
  region = var.aws_region
}
