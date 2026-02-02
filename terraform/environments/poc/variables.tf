variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name. Leave null to use environment variable AWS_PROFILE or IAM Role"
  type        = string
  default     = null
}

variable "project_name" {
  description = "Project name used for resource naming (S3 bucket prefix)"
  type        = string
  default     = "knowledge-bot"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment for AWS resources"
  type        = string
  default     = "poc"
}
