import boto3
import os
import base64
import json

from aws_secretsmanager_caching import SecretCache, SecretCacheConfig  # type: ignore[import-untyped]
from slack_sdk.signature import SignatureVerifier

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
    headers = event.get("headers", {})

    if headers.get("x-slack-retry-num"):
        return {"statusCode": 200, "body": "ok"}

    if not verify_slack_signature(event):
        return {"statusCode": 401, "body": "Invalid signature"}

    body_str = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")

    body = json.loads(body_str)
    event_type = body.get("type")

    if event_type == "url_verification":
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "text/plain"},
            "body": body.get("challenge", ""),
        }

    if event_type == "event_callback":
        slack_event = body.get("event", {})

        if slack_event.get("bot_id"):
            return {"statusCode": 200, "body": "ok"}

        event_id = body.get("event_id", "")

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
        except Exception as e:
            print(f"SQS send error: {e}")
    return {"statusCode": 200, "body": "ok"}
