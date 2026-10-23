---
name: gcp-best-practice
description: infra/（Terraform）と GCP（Cloud Run / Cloud SQL / Scheduler / Secret Manager / Artifact Registry / Workload Identity）およびデプロイ CI/CD を扱うときのこのリポジトリ固有の規約集。インフラ変更・デプロイ・環境設定・シークレット追加・マイグレーション運用の前に参照する。正本は docs/10 §3/§8、手順は infra/DEPLOY_STG.md。
---

# gcp-best-practice（infra/ + デプロイ）

構成: **GCP asia-northeast1 / Cloud Run（api・web）+ Cloud SQL(PostgreSQL) + Cloud Scheduler（日次集計）+ Secret Manager + Artifact Registry + Workload Identity(WIF)**。IaC は Terraform。正本は `docs/10 §3/§8`、stg 手順は `infra/DEPLOY_STG.md`。

## 環境とデプロイ経路

- **stg**: `main` への push で自動デプロイ（`deploy-stg.yml`、image tag = git sha）。GCP プロジェクト `shadow-ai-stg`。
- **prod**: タグ `v*` の push でデプロイ（`deploy-prod.yml`、image tag = リリースタグ）。
- 共通処理は `.github/workflows/_deploy.yml`（build&push → **Alembic マイグレーション** → Cloud Run デプロイ）。
- 認証は **Workload Identity（キーレス）**。サービスアカウントキーJSONを作らない・コミットしない。

## 規約

### Terraform（`infra/terraform/`）

- 環境差分は `environments/stg.tfvars` / `prod.tfvars` に。ハードコードしない。
- 変更前に `terraform plan`、適用は環境を明示。CI は `terraform validate` を通す。
- state はコミットしない（`.terraform/` はローカル）。プロバイダは lock ファイル（`.terraform.lock.hcl`）でバージョン固定。
- リソースは main.tf / variables.tf / outputs.tf の既存構成に合わせて追加。

### シークレット / 設定

- 秘密は **Secret Manager**。Cloud Run にはシークレット参照で注入。コード・tfvars・リポジトリに平文で置かない。
- アプリ設定は環境変数（api は `app/config.py` の `settings`、web は `API_BASE` / `SESSION_SECRET` / `NODE_ENV`）。
- GitHub 側の秘密は Actions Secrets（`STG_GCP_*` / `PROD_GCP_*`）。

### Cloud Run

- api / web を別サービス（`shadow-ai-{env}-api` / `-web`）。ステートレスに保つ。
- コンテナは arm64 slim での**ネイティブ依存の衝突に注意**（`cloud-sql-connector`→cryptography 同梱OpenSSL が SIGILL する既知問題。api はパスワードハッシュに pbkdf2_sha256 を採用済み。依存追加時はこの落とし穴を再確認）。
- DB 接続は本番のみ `cloud-sql-python-connector`（`prod` extra）。ローカル/Docker は素の Postgres。

### マイグレーション運用

- スキーマ変更は Alembic。デプロイ時に `_deploy.yml` が自動適用するため、**前方互換**（旧コードが新スキーマで動く）を意識。破壊的変更は段階移行。

## デプロイ前チェック

- [ ] CI（lint→test→build）が緑
- [ ] alembic マイグレーションの有無と前方互換を確認
- [ ] シークレット/環境変数の追加は Secret Manager / Actions Secrets 側に設定済み
- [ ] stg で挙動確認してから prod タグを打つ
- [ ] 未決事項（docs/13 §7: 本番ドメイン・プロダクト名・Slack通知先 等）が絡む変更は Ryo 判断を確認

## 原則

- 本番への操作・デプロイは外向きの操作。Ryo の依頼/明示の許可のもとで行う。
- キーレス（WIF）を崩さない。SAキーを発行しない。
- 手動でコンソールをいじって差分を作らない（Terraform を正本に保つ）。

## 参照

`infra/DEPLOY_STG.md`（実地検証済みの stg 手順） / `infra/README.md` / `docs/10 §8`
