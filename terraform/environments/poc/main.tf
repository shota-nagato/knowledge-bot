terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.30.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "poc"
      ManagedBy   = "Terraform"
    }
  }
}

module "knowledge-base" {
  source = "../../modules/knowledge-base"

  project_name = var.project_name
  environment  = var.environment
}
