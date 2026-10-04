terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60, < 7.0"
    }
  }

  # Bucket, key and region are passed at init time (-backend-config) so this
  # file stays free of account-specific values. See README.md.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "pilot-test"
      ManagedBy = "terraform"
    }
  }
}
