# =============================================================================
# Outputs
# =============================================================================

output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "state_bucket_region" {
  description = "Region of the S3 bucket"
  value       = var.aws_region
}

# =============================================================================
# Backend 設定用の出力（environments で使用）
# =============================================================================
output "backend_config" {
  description = "Backend configuration for environments"
  value       = <<-EOT
    # terraform/environments/{environment}/backend.tf にコピー
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.terraform_state.id}"
        key          = "{environment}/terraform.tfstate"
        region       = "${var.aws_region}"
        encrypt      = true
        use_lockfile = true  # S3 native locking (Terraform 1.11+)
      }
    }
  EOT
}
