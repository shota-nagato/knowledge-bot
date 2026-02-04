variable "project_name" {
  description = "Project name used as prefix for resource naming"
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Environment name (poc, stg, prd) for resource tagging and naming"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["poc", "stg", "prd"], var.environment)
    error_message = "Environment must be one of: dev, stg, prod."
  }
}

variable "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID"
  type        = string
  nullable    = false
}

variable "model_arn" {
  description = "Bedrock model ARN for answer generation"
  type        = string
  default     = "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory"
  type        = string
  nullable    = false
}
