# Knowledge Bot

Slack と Bedrock Knowledge Base を連携した社内ナレッジ検索ボットです。

## アーキテクチャ

```
Slack → Lambda Function URL → Receiver Lambda → SQS FIFO → Worker Lambda → Bedrock KB
                                                                  ↓
                                                              Slack Reply
```

## 目次

1. [前提条件](#前提条件)
2. [セットアップ](#セットアップ)
3. [Lambda 依存関係の管理](#lambda-依存関係の管理)
4. [デプロイ](#デプロイ)
5. [Slack App の設定](#slack-app-の設定)
6. [Knowledge Base の設定](#knowledge-base-の設定)
7. [トラブルシューティング](#トラブルシューティング)

---

## 前提条件

### 必要なツール

| ツール | バージョン | 用途 |
|--------|-----------|------|
| **mise** | 最新 | ツールバージョン管理 |
| **Terraform** | 1.11+ | IaC |
| **AWS CLI** | 2.x | AWS 操作 |
| **uv** | 最新 | Python パッケージ管理 |
| **Python** | 3.13+ | Lambda ランタイム |

### AWS 要件

- Bedrock モデルアクセスが有効化されていること（Claude 3 Haiku 等）
- 適切な IAM 権限があること

---

## セットアップ

### 1. ツールのインストール

```bash
# mise のインストール
brew install mise

# シェル設定に追加
eval "$(mise activate zsh)"

# プロジェクトのツールをインストール
mise install

# uv のインストール
brew install uv
```

### 2. AWS 認証

```bash
# SSO ログイン
aws sso login --profile knowledge-bot
export AWS_PROFILE=knowledge-bot

# 認証確認
aws sts get-caller-identity
```

### 3. Bootstrap（初回のみ）

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply -var="aws_account_id=${AWS_ACCOUNT_ID}"
```

---

## Lambda 依存関係の管理

Lambda の依存関係は `uv` で管理し、`requirements.txt` を各ディレクトリにコピーします。

### 依存関係の更新手順

```bash
cd lambda

# 1. pyproject.toml を編集（必要に応じて）

# 2. ロックファイルを更新
uv lock

# 3. requirements.txt を生成
uv export --frozen --no-dev --no-editable -o requirements.txt

# 4. 各 Lambda ディレクトリにコピー
cp requirements.txt receiver/
cp requirements.txt worker/
```

### ディレクトリ構成

```
lambda/
├── pyproject.toml          # 共通の依存関係定義
├── uv.lock                 # ロックファイル
├── receiver/
│   ├── handler.py
│   └── requirements.txt    # ← uv export で生成してコピー
└── worker/
    ├── handler.py
    └── requirements.txt    # ← uv export で生成してコピー
```

---

## デプロイ

```bash
cd terraform/environments/poc
terraform init
terraform plan
terraform apply
```

---

## Slack App の設定

### 1. Slack App の作成

1. [Slack API](https://api.slack.com/apps) で新しいアプリを作成
2. **OAuth & Permissions** → **Bot Token Scopes** に以下を追加：
   - `app_mentions:read`
   - `chat:write`
3. **Install to Workspace** をクリック

### 2. シークレットの設定

```bash
# Bot Token（xoxb-...）を設定
aws secretsmanager put-secret-value \
  --secret-id "knowledge-bot/poc/slack-bot-token" \
  --secret-string "xoxb-YOUR-BOT-TOKEN" \
  --region ap-northeast-1

# Signing Secret を設定
aws secretsmanager put-secret-value \
  --secret-id "knowledge-bot/poc/slack-signing-secret" \
  --secret-string "YOUR-SIGNING-SECRET" \
  --region ap-northeast-1
```

### 3. Event Subscriptions の設定

1. **Event Subscriptions** → **Enable Events** を ON
2. **Request URL** に Lambda Function URL を入力
3. **Subscribe to bot events** に `app_mention` を追加
4. Bot をチャンネルに招待: `/invite @bot-name`

---

## Knowledge Base の設定

### 1. ドキュメントを S3 にアップロード

```bash
# バケット名を確認
aws s3 ls | grep knowledge-bot

# ドキュメントをアップロード
aws s3 cp your-document.pdf s3://knowledge-bot-poc-source-bucket/documents/ \
  --region ap-northeast-1
```

### 2. データソースの同期

S3 にアップロードしただけでは Knowledge Base に反映されません。同期が必要です。

```bash
# Knowledge Base ID を確認
aws bedrock-agent list-knowledge-bases --region ap-northeast-1

# Data Source ID を確認
aws bedrock-agent list-data-sources \
  --knowledge-base-id YOUR_KB_ID \
  --region ap-northeast-1

# 同期を実行
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id YOUR_KB_ID \
  --data-source-id YOUR_DATASOURCE_ID \
  --region ap-northeast-1
```

同期が完了するまで数分かかります。

---

## トラブルシューティング

### Secrets Manager アクセスエラー

```
AccessDeniedException: secretsmanager:DescribeSecret
```

**原因**: Lambda の IAM ロールに `DescribeSecret` 権限がない

**解決策**: Terraform の `policy_statements` に以下を追加：

```hcl
actions = [
  "secretsmanager:GetSecretValue",
  "secretsmanager:DescribeSecret",  # ← 追加
]
```

### Slack URL 検証エラー

```
Your URL didn't respond with the value of the challenge parameter.
```

**原因**: Lambda が正しく応答していない

**確認方法**:

```bash
aws logs tail /aws/lambda/knowledge-bot-poc-receiver --region ap-northeast-1 --since 5m
```

**よくある原因**:
- Signing Secret が正しく設定されていない
- IAM 権限が不足している

### Bedrock モデルアクセスエラー

```
Model access is denied due to IAM user or service role is not authorized
```

**解決策**:

1. [Bedrock コンソール](https://ap-northeast-1.console.aws.amazon.com/bedrock/home?region=ap-northeast-1#/modelaccess) でモデルアクセスを有効化
2. 2分待ってから再試行

### Bedrock Inference Profile エラー

```
Invocation of model ID anthropic.claude-3-5-sonnet-... with on-demand throughput isn't supported
```

**原因**: Claude 3.5 Sonnet v2 などの新しいモデルは Inference Profile が必要

**解決策**: Claude 3 Haiku など、オンデマンドで利用可能なモデルに変更：

```hcl
# terraform/modules/slack-bot/variables.tf
variable "model_arn" {
  default = "arn:aws:bedrock:ap-northeast-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
}
```

### SQS にメッセージが届かない

**確認方法**:

```bash
# Lambda ログを確認
aws logs tail /aws/lambda/knowledge-bot-poc-receiver --region ap-northeast-1 --since 5m

# SQS メッセージを確認
aws sqs receive-message \
  --queue-url "https://sqs.ap-northeast-1.amazonaws.com/ACCOUNT_ID/knowledge-bot-poc-events.fifo" \
  --region ap-northeast-1
```

**よくある原因**:
- Bot がチャンネルに招待されていない
- Event Subscriptions で `app_mention` が設定されていない

### Lambda パス解決エラー

```
RuntimeError: File not found: /path/to/lambda/receiver
```

**原因**: Terraform の `lambda_source_dir` パスが正しくない

**解決策**: `abspath()` を使用しない場合、相対パスの階層を確認：

```hcl
# terraform/environments/poc から見て lambda/ への正しいパス
lambda_source_dir = "${path.root}/../../../lambda"
```

### Knowledge Base から回答が得られない

```
該当する情報が見つかりませんでした
```

**確認事項**:

1. S3 にドキュメントがアップロードされているか
2. データソースの同期が完了しているか
3. 同期ジョブのステータスを確認：

```bash
aws bedrock-agent list-ingestion-jobs \
  --knowledge-base-id YOUR_KB_ID \
  --data-source-id YOUR_DATASOURCE_ID \
  --region ap-northeast-1
```

---

## 参照リンク

- [AWS Bedrock Knowledge Base](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
- [Slack API - Event Subscriptions](https://api.slack.com/events-api)
- [terraform-aws-modules/lambda](https://github.com/terraform-aws-modules/terraform-aws-lambda)
- [uv - Python パッケージマネージャー](https://github.com/astral-sh/uv)
