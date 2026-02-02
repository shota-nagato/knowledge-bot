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

variable "embedding_model" {
  description = "The model used to create vector embeddings for the knowledge base"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}
