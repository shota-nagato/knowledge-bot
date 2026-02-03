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
          "arn:aws:bedrock:${local.region}::foundation-model/${var.embedding_model}"
        ]
      }
    ]
  })
}
