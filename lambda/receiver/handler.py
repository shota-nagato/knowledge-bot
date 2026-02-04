import boto3
import os
import base64
import json
import logging

from aws_secretsmanager_caching import SecretCache, SecretCacheConfig  # type: ignore[import-untyped]
from slack_sdk.signature import SignatureVerifier

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client("sqs")
secrets = boto3.client("secretsmanager")

QUEUE_URL = os.environ["SQS_QUEUE_URL"]
SIGNING_SECRET_ARN = os.environ["SIGNING_SECRET_ARN"]

cache_config = SecretCacheConfig(secret_refresh_interval=300)
cache = SecretCache(config=cache_config)


def get_signing_secret():
    """Signing Secretをキャッシュ付きで取得"""
    return cache.get_secret_string(SIGNING_SECRET_ARN)


def verify_slack_signature(event):
    """Slack署名検証"""
    verifier = SignatureVerifier(get_signing_secret())

    return verifier.is_valid_request(
        body=event.get("body", ""), headers=event.get("headers", {})
    )


def handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")

    headers = event.get("headers", {})

    if headers.get("x-slack-retry-num"):
        logger.info("Skipping retry request")
        return {"statusCode": 200, "body": "ok"}

    if not verify_slack_signature(event):
        logger.warning("Signature verification failed")
        return {"statusCode": 401, "body": "Invalid signature"}

    body_str = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")

    body = json.loads(body_str)
    event_type = body.get("type")
    logger.info(f"Event type: {event_type}")

    if event_type == "url_verification":
        logger.info("Handling url_verification")
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "text/plain"},
            "body": body.get("challenge", ""),
        }

    if event_type == "event_callback":
        slack_event = body.get("event", {})
        logger.info(f"Slack event: {json.dumps(slack_event)}")

        if slack_event.get("bot_id"):
            logger.info("Skipping bot message")
            return {"statusCode": 200, "body": "ok"}

        event_id = body.get("event_id", "")
        logger.info(f"Processing event_id: {event_id}")

        try:
            sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=json.dumps(
                    {
                        "event": slack_event,
                        "event_id": event_id,
                        "event_time": body.get("event_time", ""),
                    }
                ),
                MessageGroupId="slack-events",
                MessageDeduplicationId=event_id,
            )
            logger.info(f"Message sent to SQS: {event_id}")
        except Exception as e:
            logger.error(f"SQS send error: {e}", exc_info=True)

    return {"statusCode": 200, "body": "ok"}
