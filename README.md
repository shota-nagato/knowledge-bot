# Terraform セットアップガイド

このドキュメントでは、AWS/Terraform 環境の準備手順を説明します。

## 目次

1. [前提条件](#前提条件)
2. [ローカル環境のセットアップ](#ローカル環境のセットアップ)
3. [AWS 認証の設定](#aws-認証の設定)
4. [Bootstrap の実行](#bootstrap-の実行)
5. [環境の構築](#環境の構築)
6. [ディレクトリ構成](#ディレクトリ構成)
7. [環境変数リファレンス](#環境変数リファレンス)
8. [トラブルシューティング](#トラブルシューティング)
9. [セキュリティベストプラクティス](#セキュリティベストプラクティス)
10. [参照リンク](#参照リンク)

---

## 前提条件

### 必要なツール

| ツール | バージョン | 用途 |
|--------|-----------|------|
| **mise** | 最新 | ツールバージョン管理 |
| **Terraform** | 1.11+ | IaC（mise で自動インストール） |
| **AWS CLI** | 2.x | AWS 操作 |
| **Docker** | 最新 | コンテナビルド |

### AWS アカウント要件

- AWS アカウントを持っていること
- IAM Identity Center（AWS SSO）または IAM ユーザーでの認証が可能なこと
- 以下のサービスへのアクセス権限があること：
  - S3, DynamoDB, VPC, ECS, ECR, RDS, Cognito, ALB, CloudFront

---

## ローカル環境のセットアップ

### 1. mise のインストール

```bash
# macOS (Homebrew)
brew install mise

# Linux
curl https://mise.run | sh

# インストール確認
mise --version
```

### 2. シェル設定

```bash
# ~/.zshrc または ~/.bashrc に追加
eval "$(mise activate zsh)"  # zsh の場合
eval "$(mise activate bash)" # bash の場合

# 設定を反映
source ~/.zshrc
```

### 3. プロジェクトディレクトリでツールをインストール

```bash
# mise が mise.toml を読み込んで Terraform を自動インストール
mise install

# インストール確認
terraform version
# Terraform v1.11.4
```

### 4. AWS CLI のインストール

```bash
# macOS (Homebrew)
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# 確認
aws --version
```

---

## AWS 認証の設定

### Option A: IAM Identity Center（AWS SSO）- 推奨

AWS Organizations を使用している場合は、IAM Identity Center（旧 AWS SSO）を推奨します。

#### A-1. SSO セッションの設定

```bash
aws configure sso
```

対話式で以下を入力：

```
SSO session name: knowledge-bot-sso
SSO start URL: https://your-org.awsapps.com/start  # AWS コンソールで確認
SSO region: ap-northeast-1
SSO registration scopes: sso:account:access
→ ブラウザが開き認証
Account ID: 選択
Role: AdministratorAccess（または適切な権限）
CLI default client Region: ap-northeast-1
CLI default output format: json
CLI profile name: knowledge-bot
```

#### A-2. プロファイルの確認

`~/.aws/config` に以下が追加されます：

```ini
[profile knowledge-bot]
sso_session = knowledge-bot-sso
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = ap-northeast-1
output = json

[sso-session knowledge-bot-sso]
sso_start_url = https://your-org.awsapps.com/start
sso_region = ap-northeast-1
sso_registration_scopes = sso:account:access
```

### Option B: IAM ユーザー（アクセスキー）

> **注意**: 長期的なアクセスキーはセキュリティリスクがあります。可能な限り SSO を使用してください。

```bash
aws configure --profile knowledge-bot
```

```
AWS Access Key ID: AKIA...
AWS Secret Access Key: ****
Default region name: ap-northeast-1
Default output format: json
```

### 認証の確認

```bash
# プロファイルを指定して確認
AWS_PROFILE=knowledge-bot aws sts get-caller-identity
```

出力例：

```json
{
    "UserId": "AROA...",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/..."
}
```

---

## Bootstrap の実行

Bootstrap は Terraform State を保存する S3 バケットを作成します。

### 1. SSO ログイン

```bash
aws sso login --profile knowledge-bot
export AWS_PROFILE=knowledge-bot
```

### 2. AWS Account ID を取得

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${AWS_ACCOUNT_ID}"
```

### 3. Terraform の初期化と実行

```bash
# 初期化
terraform -chdir=terraform/bootstrap init

# 実行計画の確認
terraform -chdir=terraform/bootstrap plan -var="aws_account_id=${AWS_ACCOUNT_ID}"

# 適用
terraform -chdir=terraform/bootstrap apply -var="aws_account_id=${AWS_ACCOUNT_ID}"
```

### 4. 出力を確認

environments の backend 設定に使用する値を確認します。

```bash
terraform -chdir=terraform/bootstrap output backend_config
```

### 作成されるリソース

| リソース | 用途 |
|---------|------|
| S3 バケット | Terraform State の保存 |
| S3 暗号化設定 | State の暗号化（AES256） |
| S3 バージョニング | State の履歴管理 |
| S3 パブリックアクセスブロック | セキュリティ |

---

## 環境の構築

Bootstrap 完了後、以下の手順で環境を構築します。

### poc 環境

```bash
terraform -chdir=terraform/environments/poc init
terraform -chdir=terraform/environments/poc plan
terraform -chdir=terraform/environments/poc apply
```

---

## ディレクトリ構成

```
terraform/
├── bootstrap/                # State 管理用 S3 バケット
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── environments/
    └── poc/                  # PoC 環境
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── backend.tf        # S3 backend 設定
```

---

## 環境変数リファレンス

| 変数 | 説明 | 例 |
|------|------|-----|
| `AWS_PROFILE` | AWS CLI プロファイル名 | `knowledge-bot` |
| `AWS_REGION` | AWS リージョン（オプション） | `ap-northeast-1` |
| `TF_VAR_xxx` | Terraform 変数の上書き | `TF_VAR_environment=poc` |

---

## トラブルシューティング

### mise でツールがインストールされない

```bash
# キャッシュをクリアして再インストール
mise cache clear
mise install
```

### AWS 認証エラー

```
Error: No valid credential sources found
```

**対処法**:

```bash
# SSO の場合、再ログイン
aws sso login --profile knowledge-bot

# プロファイルが正しく設定されているか確認
aws configure list --profile knowledge-bot
```

### SSO Session エラー（Terraform で SSO が使えない）

```
Error: failed to find SSO session section, aws configure sso
```

**原因**: Terraform の AWS Provider が `sso-session` 形式（AWS CLI v2 の新形式）を完全にサポートしていないため発生します。AWS CLI では認証成功するのに Terraform では失敗するケースがあります。

**対処法**: `~/.aws/config` をレガシー形式に変更します。

**変更前（新形式 - Terraform で動作しない場合がある）**:

```ini
[profile knowledge-bot]
sso_session = knowledge-bot-sso
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = ap-northeast-1
output = json

[sso-session knowledge-bot-sso]
sso_start_url = https://d-xxxxxx.awsapps.com/start
sso_region = ap-northeast-1
sso_registration_scopes = sso:account:access
```

**変更後（レガシー形式 - Terraform 互換）**:

```ini
[profile knowledge-bot]
sso_start_url = https://d-xxxxxx.awsapps.com/start
sso_region = ap-northeast-1
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = ap-northeast-1
output = json
```

変更後、再ログインを実行：

```bash
aws sso logout --profile knowledge-bot
aws sso login --profile knowledge-bot
terraform -chdir=terraform/bootstrap plan
```

**参考**:

- [hashicorp/terraform-provider-aws#28263](https://github.com/hashicorp/terraform-provider-aws/issues/28263)
- [hashicorp/terraform#32465](https://github.com/hashicorp/terraform/issues/32465)

### Terraform State ロックエラー

```
Error: Error acquiring the state lock
```

**対処法**:

```bash
# 強制的にロックを解除（他の操作が進行中でないことを確認）
terraform force-unlock <LOCK_ID>
```

### S3 バケット作成エラー（名前重複）

```
Error: Error creating S3 bucket: BucketAlreadyExists
```

**対処法**: バケット名はグローバルで一意である必要があります。`project_name` または `aws_account_id` を含めて一意にしてください。

### Provider のバージョンエラー

```
Error: Unsupported Terraform Core version
```

**対処法**:

```bash
# mise で正しいバージョンを使用しているか確認
terraform version

# バージョンが異なる場合
mise install terraform@1.11.4
```

---

## セキュリティベストプラクティス

### 必須

- [ ] `terraform.tfvars` を `.gitignore` に追加
- [ ] S3 バケットの暗号化を有効化
- [ ] S3 バケットのパブリックアクセスをブロック
- [ ] IAM で最小権限の原則を適用

### 推奨

- [ ] IAM Identity Center（SSO）を使用
- [ ] MFA を有効化
- [ ] CloudTrail で API 操作をログ記録
- [ ] CI/CD では OIDC 認証を使用（長期アクセスキー不使用）

---

## 参照リンク

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS CLI v2 設定ガイド](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [mise ドキュメント](https://mise.jdx.dev/)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/backend/s3)
