import json
import logging
import boto3
import os

from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Clients
bedrock = boto3.client("bedrock-agent-runtime")
secrets = boto3.client("secretsmanager")

# Environment variables
BOT_TOKEN_ARN = os.environ["BOT_TOKEN_ARN"]
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
MODEL_ARN = os.environ.get(
    "MODEL_ARN",
    "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
)

_slack_client = None


def get_slack_client():
    """Slack WebClientをキャッシュ付きで取得"""
    global _slack_client
    if _slack_client is None:
        response = secrets.get_secret_value(SecretId=BOT_TOKEN_ARN)
        _slack_client = WebClient(token=response["SecretString"])
    return _slack_client


PROMPT_TEMPLATE = """あなたは社内ナレッジを検索して回答するアシスタントです。
以下の検索結果を元に、質問に日本語で簡潔に回答してください。

回答のルール:
1. 検索結果に該当する情報がある場合は、その情報を元に回答してください
2. 検索結果に該当する情報がない場合は「該当する情報が見つかりませんでした」と回答してください
3. 推測や一般的な知識での補完は最小限にしてください
4. 手順を説明する場合は、番号付きリストで分かりやすく記載してください

検索結果:
$search_results$

質問: $query$

回答:"""


def query_knowledge_base(query):
    """Bedrock Knowledge Baseに問い合わせて回答を取得"""
    try:
        response = bedrock.retrieve_and_generate(
            input={"text": query},
            retrieveAndGenerateConfiguration={
                "type": "KNOWLEDGE_BASE",
                "knowledgeBaseConfiguration": {
                    "knowledgeBaseId": KNOWLEDGE_BASE_ID,
                    "modelArn": MODEL_ARN,
                    "generationConfiguration": {
                        "promptTemplate": {"textPromptTemplate": PROMPT_TEMPLATE},
                    },
                },
            },
        )

        answer = response["output"]["text"]

        # ソース（引用元）を取得
        sources = []
        for citation in response.get("citations", []):
            for reference in citation.get("retrievedReferences", []):
                location = reference.get("location", {})
                s3_location = location.get("s3Location", {})
                if s3_location:
                    uri = s3_location.get("uri", "")
                    # S3 URI からファイル名を抽出
                    filename = uri.split("/")[-1] if uri else ""
                    if filename and filename not in sources:
                        sources.append(filename)

        # ソースがあれば回答に追加
        if sources:
            answer += "\n\n📚 *参照元:*\n" + "\n".join(f"• {s}" for s in sources)

        return answer

    except Exception as e:
        logger.error(f"Bedrock error: {e}", exc_info=True)
        return "申し訳ありません。回答の生成中にエラーが発生しました。"


def send_slack_message(channel, text, thread_ts=None):
    """Slackにメッセージを送信"""
    try:
        client = get_slack_client()
        client.chat_postMessage(
            channel=channel,
            text=text,
            thread_ts=thread_ts,
        )
        logger.info(f"Message sent to {channel}")
    except SlackApiError as e:
        logger.error(f"Slack API error: {e}", exc_info=True)
        raise


def handler(event, context):
    """SQSトリガーで実行されるワーカー"""
    logger.info(f"Received {len(event.get('Records', []))} records")

    failed_message_ids = []

    for record in event.get("Records", []):
        message_id = record.get("messageId")
        try:
            message = json.loads(record["body"])
            slack_event = message.get("event", {})
            event_id = message.get("event_id")

            logger.info(f"Processing event: {event_id}")

            channel = slack_event.get("channel")
            text = slack_event.get("text", "")
            thread_ts = slack_event.get("ts")

            # メンション部分を除去してクエリを抽出
            # 例: "<@U0ACXLUV9N2> Hello!" -> "Hello!"
            query = " ".join(
                word for word in text.split() if not word.startswith("<@")
            ).strip()

            if not query:
                query = text

            logger.info(f"Query: {query}")

            # Bedrock Knowledge Base で回答生成
            answer = query_knowledge_base(query)
            logger.info(f"Answer generated: {answer[:100]}...")

            # Slackに返信
            send_slack_message(channel, answer, thread_ts)

        except Exception as e:
            logger.error(f"Error processing message {message_id}: {e}", exc_info=True)
            failed_message_ids.append(message_id)

    # 失敗したメッセージを報告（SQSが再処理）
    if failed_message_ids:
        return {
            "batchItemFailures": [
                {"itemIdentifier": msg_id} for msg_id in failed_message_ids
            ]
        }

    return {"statusCode": 200}
