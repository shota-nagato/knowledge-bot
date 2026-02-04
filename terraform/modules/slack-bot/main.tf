data "aws_region" "current" {}

locals {
  prefix = "${var.project_name}-${var.environment}"
  region = data.aws_region.current.region
}

# =============================================================================
# Secrets Manager - Slack認証情報
# =============================================================================
resource "aws_secretsmanager_secret" "slack_bot_token" {
  name                    = "${var.project_name}/${var.environment}/slack-bot-token"
  description             = "Slack Bot OAuth Token (xoxb-xxx)"
  recovery_window_in_days = var.environment == "poc" ? 0 : 30
}

resource "aws_secretsmanager_secret_version" "slack_bot_token" {
  secret_id     = aws_secretsmanager_secret.slack_bot_token.id
  secret_string = "UPDATE_MANUALLY"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "slack_signing_secret" {
  name                    = "${var.project_name}/${var.environment}/slack-signing-secret"
  description             = "Slack App Signing Secret"
  recovery_window_in_days = var.environment == "poc" ? 0 : 30
}

resource "aws_secretsmanager_secret_version" "slack_signing_secret" {
  secret_id     = aws_secretsmanager_secret.slack_signing_secret.id
  secret_string = "UPDATE_MANUALLY"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# =============================================================================
# SQS FIFO Queue - Slack 3秒タイムアウト対策
# =============================================================================
resource "aws_sqs_queue" "events" {
  name                        = "${local.prefix}-events.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"

  visibility_timeout_seconds = 180
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue" "events_dlq" {
  name                        = "${local.prefix}-events-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
}

# =============================================================================
# Lambda - Receiver (即時応答 + SQS送信)
# =============================================================================
module "ack_lambda" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "${local.prefix}-receiver"
  description   = "Slack Events receiver - immediate ack and queue to SQS"
  handler       = "handler.handler"
  runtime       = "python3.13"
  architectures = ["arm64"]
  timeout       = 10
  memory_size   = 256

  source_path = [
    {
      path             = "${var.lambda_source_dir}/receiver"
      pip_requirements = true
      patterns = [
        "!\\.venv/.*",
        "!__pycache__/.*",
        "!\\.pytest_cache/.*",
      ]
    }
  ]

  environment_variables = {
    SQS_QUEUE_URL      = aws_sqs_queue.events.url
    SIGNING_SECRET_ARN = aws_secretsmanager_secret.slack_signing_secret.arn
  }

  attach_policy_statements = true
  policy_statements = {
    sqs = {
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.events.arn]
    }
    secrets = {
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = [aws_secretsmanager_secret.slack_signing_secret.arn]
    }
  }

  create_lambda_function_url = true
  authorization_type         = "NONE"

  cloudwatch_logs_retention_in_days = 14
}

# =============================================================================
# Lambda - Worker (Bedrock処理 + Slack返信)
# =============================================================================
module "worker_lambda" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "${local.prefix}-worker"
  description   = "Process Slack events with Bedrock and reply"
  handler       = "handler.handler"
  runtime       = "python3.13"
  architectures = ["arm64"]
  timeout       = 180
  memory_size   = 512

  source_path = [
    {
      path             = "${var.lambda_source_dir}/worker"
      pip_requirements = true
      patterns = [
        "!\\.venv/.*",
        "!__pycache__/.*",
        "!\\.pytest_cache/.*",
      ]
    }
  ]

  environment_variables = {
    BOT_TOKEN_ARN     = aws_secretsmanager_secret.slack_bot_token.arn
    KNOWLEDGE_BASE_ID = var.knowledge_base_id
    MODEL_ARN         = var.model_arn
  }

  attach_policy_statements = true
  policy_statements = {
    secrets = {
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = [aws_secretsmanager_secret.slack_bot_token.arn]
    }
    bedrock = {
      effect = "Allow"
      actions = [
        "bedrock:InvokeModel",
        "bedrock:RetrieveAndGenerate",
        "bedrock:Retrieve",
      ]
      resources = ["*"]
    }
    marketplace = {
      effect = "Allow"
      actions = [
        "aws-marketplace:ViewSubscriptions",
        "aws-marketplace:Subscribe",
      ]
      resources = ["*"]
    }
    sqs = {
      effect = "Allow"
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
      ]
      resources = [aws_sqs_queue.events.arn]
    }
  }

  event_source_mapping = {
    sqs = {
      event_source_arn        = aws_sqs_queue.events.arn
      function_response_types = ["ReportBatchItemFailures"]
    }
  }

  cloudwatch_logs_retention_in_days = 14
}
