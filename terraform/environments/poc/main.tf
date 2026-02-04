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

  project_name    = var.project_name
  environment     = var.environment
  embedding_model = "amazon.titan-embed-text-v2:0"
}

module "slack-bot" {
  source = "../../modules/slack-bot"

  project_name      = var.project_name
  environment       = var.environment
  lambda_source_dir = "${path.root}/../../../lambda"
  knowledge_base_id = module.knowledge-base.knowledge_base_id
}
