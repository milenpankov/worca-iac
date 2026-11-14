terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local state for the PoC. For anything shared, move it to S3: see ../aws-eks/README.md, "State".
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
