data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix     = "${var.project_name}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

# =============================================================================
# S3バケット (ドキュメント格納用)
# =============================================================================
resource "aws_s3_bucket" "main" {
  bucket        = "${local.prefix}-source-bucket"
  force_destroy = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# =============================================================================
# S3 Vectors
# =============================================================================
resource "aws_s3vectors_vector_bucket" "main" {
  vector_bucket_name = "${local.prefix}-vector-bucket"

  encryption_configuration {
    sse_type = "AES256"
  }
}

resource "aws_s3vectors_index" "main" {
  index_name         = "${local.prefix}-vectors-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.main.vector_bucket_name

  data_type       = "float32"
  dimension       = 1024
  distance_metric = "cosine"
}

# =============================================================================
# Bedrock Knowledge Base
# =============================================================================
resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "${local.prefix}-kb"
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${local.region}::foundation-model/${var.embedding_model}"
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.main.index_arn
    }
  }
}

# =============================================================================
# Bedrock Data Source (S3)
# =============================================================================
resource "aws_bedrockagent_data_source" "main" {
  name              = "${local.prefix}-datasource"
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.main.arn
    }
  }
}
