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

# variable "knowledge_base_id" {
#   description = "Bedrock Knowledge Base ID"
#   type        = string
#   nullable    = false
# }

# variable "model_id" {
#   description = "Bedrock model ID for Answer generation"
#   type        = string
#   default     = ""
# }

variable "lambda_source_dir" {
  description = "Path to lambda source directory"
  type        = string
  nullable    = false
}
