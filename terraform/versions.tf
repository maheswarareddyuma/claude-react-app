terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.57"
    }
  }

  # Partial config. CI passes the rest with -backend-config (see .github/workflows/deploy.yml).
  # use_lockfile = S3-native state locking, no DynamoDB table needed (TF >= 1.10).
  backend "s3" {
    key          = "react-app/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region
}
