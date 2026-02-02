data "aws_caller_identity" "current" {}

locals {
  prefix     = "${var.project_name}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
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
# IAM Role for Bedrock Knowledge Base
# =============================================================================

resource "aws_iam_role" "bedrock_kb" {
  name = "${local.prefix}-bedrock-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# =============================================================================
# IAM Policy for Bedrock Knowledge Base
# =============================================================================
resource "aws_iam_role_policy" "bedrock_kb" {
  name = "${local.prefix}-bedrock-kb-policy"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 ソースバケット - ListBucket
      {
        Sid    = "S3ListBucketStatement"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.main.arn
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
          }
        }
      },
      # S3 ソースバケット - GetObject
      {
        Sid    = "S3GetObjectStatement"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.main.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
          }
        }
      },
      # S3 Vectors アクセス
      {
        Sid    = "S3VectorBucketReadAndWritePermission"
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:GetVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:QueryVectors",
          "s3vectors:GetIndex"
        ]
        Resource = aws_s3vectors_index.main.index_arn
      },
      # 埋め込みモデル呼び出し
      {
        Sid    = "BedrockInvokeModelStatement"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
        ]
      }
    ]
  })
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
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
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
