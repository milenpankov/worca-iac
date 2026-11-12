terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local state for the PoC (terraform.tfstate here; the platform root reads it). For anything
  # shared, move to S3: see ../README.md, "State".
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
