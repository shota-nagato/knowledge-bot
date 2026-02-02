terraform {
  backend "s3" {
    bucket       = "knowledge-bot-terraform-state-205930625330"
    key          = "poc/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true # S3 native locking (Terraform 1.11+)
  }
}
