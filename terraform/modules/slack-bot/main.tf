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
