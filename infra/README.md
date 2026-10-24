# インフラ（Terraform）

Cloudflare と Google Cloud（GCP）のリソースを Terraform で管理する．目標とするクラウド構成・接続・秘密情報の方針は[インフラ構成](../docs/spec/2.インフラ構成.md)を正本とし，本書は Terraform のディレクトリ構成・管理範囲・運用手順を定める．

**現在は方針のみで，Terraform コード・クラウドリソースは未作成．** 本書の「未決事項」は実装前に決める．

## 1. 管理範囲

| 対象 | Terraform で管理するもの | Terraform で管理しないもの |
| --- | --- | --- |
| GCP | API 有効化，Artifact Registry，Cloud Run サービス設定（SA・環境変数・Secret 参照・スケール），Secret Manager の器，サービスアカウントと IAM，GitHub Actions 用 Workload Identity 連携，tfstate 用 GCS バケット | コンテナイメージのビルド・公開，Cloud Run へのイメージ更新（CI／`gcloud` が担当），Secret の値 |
| Cloudflare | API 用 DNS レコード，ゾーンの SSL/TLS・セキュリティ設定，WAF・レート制限ルール | ドメイン取得・ゾーン作成（手動），アカウント・API トークンの発行 |
| Supabase | 当面は対象外 | プロジェクト作成・Auth 設定・DB 接続情報の取得（Dashboard で手動） |
| DB スキーマ | 対象外 | 業務スキーマは backend の goose が正本．`auth` スキーマは Supabase 管理 |

方針:

- **アプリのデプロイとインフラ設定を分ける．** Cloud Run のイメージは CI が更新するため，Terraform 側は `lifecycle.ignore_changes` でイメージを差分対象から外す．環境変数・SA・スケール等の設定変更は Terraform で行う．
- **秘密の値を tfstate・リポジトリに入れない．** Secret Manager の Secret（器）と IAM は Terraform で作り，値（`DATABASE_URL` 等）は `gcloud secrets versions add` で手動投入する．Cloud Run は Secret を参照する．
- Cloudflare の API トークン・GCP の認証情報は環境変数（`CLOUDFLARE_API_TOKEN`，ADC）から渡し，`*.tf`・`*.tfvars` に書かない．

## 2. ディレクトリ構成

```text
infra/
├── README.md
├── bootstrap/                  # 最初に1回だけ適用．tfstate 用 GCS バケット・必要 API の有効化（state はローカル）
├── modules/                    # dev/prod で繰り返す構成だけをモジュール化
│   ├── gcp/
│   │   └── cloud-run-api/      # Cloud Run サービス，実行用 SA，Secret 参照の IAM
│   └── cloudflare/
│       └── api-endpoint/       # 環境ごとの API ホスト名の DNS レコード・ホスト単位のルール
└── envs/                       # 適用単位（ルートモジュール）．1ディレクトリ = 1 state
    ├── shared/
    │   ├── gcp/                # Artifact Registry，CI 用 SA・Workload Identity 連携
    │   └── cloudflare/         # ゾーン共通設定（SSL/TLS モード，WAF マネージドルール等）
    ├── dev/
    │   ├── gcp/                # modules/gcp/cloud-run-api を dev 設定で呼ぶ
    │   └── cloudflare/         # modules/cloudflare/api-endpoint を dev 設定で呼ぶ
    └── prod/
        ├── gcp/
        └── cloudflare/
```

各ルートモジュール（`bootstrap/`，`envs/*/*`）は次のファイルで構成する．

| ファイル | 内容 |
| --- | --- |
| `versions.tf` | `required_version` と `required_providers`（バージョン制約） |
| `providers.tf` | provider 設定．認証情報は書かない |
| `backend.tf` | GCS backend（bucket と `prefix`） |
| `main.tf` | リソース・モジュール呼び出し．大きくなったら役割ごとにファイルを分ける |
| `variables.tf` / `outputs.tf` | 入力・出力 |
| `terraform.tfvars` | 秘密を含まない環境固有値（プロジェクト ID，リージョン，ホスト名等）．コミットする |
| `.terraform.lock.hcl` | provider のロック．コミットする |

### 構成の考え方

- **プロバイダーごとに state を分ける．** Cloudflare と GCP は認証情報・変更頻度・権限を持つ人が異なるため，同じ環境でも `gcp/` と `cloudflare/` を別 state にする．一方の plan に他方の認証情報が不要になり，誤操作の影響範囲も狭まる．
- **環境ごとに state を分ける．** dev の apply が prod に波及しないよう，`envs/dev` と `envs/prod` は別ディレクトリ・別 state とし，差分は `terraform.tfvars` に寄せる．Terraform workspace は使わない（どの環境を操作しているかがディレクトリで明示されるため）．
- **環境をまたぐ共有物は `shared/` に置く．** Cloudflare のゾーン設定は dev/prod のホスト名で共有されるため，環境別 state に置くと二重管理になる．Artifact Registry・CI 用の認証も同様．
- **依存は一方向にする．** `envs/<env>/cloudflare` は `envs/<env>/gcp` の出力（Cloud Run の接続先）を `terraform_remote_state` で読み取るだけで，逆方向の参照は作らない．
- **モジュール化は最小限にする．** dev/prod で繰り返す構成だけを `modules/` に置き，`shared/` でしか使わないリソースは直接書く．

### state

- `bootstrap/` で作る GCS バケット（バージョニング有効，公開アクセス禁止）に全ルートモジュールの state を保存する．Cloudflare の state も同じバケットに置く．
- `prefix` はディレクトリと一致させる（例: `envs/prod/gcp`）．
- `bootstrap/` 自身の state はローカルに置き，コミットしない．作り直しが必要になった場合は `terraform import` で復元する．

## 3. 適用順序

```text
bootstrap → envs/shared/gcp → envs/shared/cloudflare → envs/<env>/gcp → envs/<env>/cloudflare
```

`envs/<env>/gcp` の apply 後，Secret の値を手動投入し，CI（または手動）で最初のイメージをデプロイしてから疎通確認する．

```bash
cd infra/envs/dev/gcp
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

apply 前に必ず plan を確認する．prod の apply は plan 結果をレビューしてから行う．

## 4. 命名規則

- リソース名: `tkb-<env>-<役割>`（例: `tkb-prod-api`，`tkb-dev-api-runtime`）．環境共有物は `tkb-<役割>`．
- Terraform のリソースラベル（`resource "..." "<名前>"`）は snake_case，役割を表す名前にする（`this` は単一リソースのモジュール内のみ）．
- GCP リソースには `env`・`managed-by = terraform` ラベルを付ける．

## 5. 未決事項

| 項目 | 選択肢・推奨 | 決める時期 |
| --- | --- | --- |
| Cloudflare → Cloud Run の接続方式 | 下表参照 | `envs/<env>/cloudflare` 実装前 |
| 環境数 | dev/prod の2環境を推奨（Supabase 無料枠のプロジェクト数とも合う）．prod のみで始めても構成は変わらない | 最初の apply 前 |
| GCP プロジェクトの分け方 | ハッカソン期間はクレジット・課金管理を簡単にするため1プロジェクトで環境をリソース名で分けることを推奨．長期運用なら環境別プロジェクト | `bootstrap/` 実装前 |
| リージョン | Cloud Run・Artifact Registry は `asia-northeast1`（東京），Supabase も東京リージョンにそろえる案 | `bootstrap/` 実装前 |
| ドメイン | 使用するドメインと Cloudflare ゾーンの有無，API ホスト名（例: `api.<domain>`，`api-dev.<domain>`） | `envs/shared/cloudflare` 実装前 |
| Terraform の実行場所 | ローカル実行で開始し，GitHub Actions（Workload Identity 連携）で PR に plan を出す運用へ移行する案 | CI 整備時 |
| Terraform / provider のバージョン | 実装時点の最新安定版に固定し，`.terraform.lock.hcl` をコミットする | 実装時 |
| goose マイグレーションの実行 | Cloud Run Jobs で `cmd/migrate` を実行する案（`MIGRATION_DATABASE_URL` を使う） | PostgreSQL 移行時 |
| Supabase の Terraform 管理 | 当面は手動．設定項目が増えたら Supabase provider の導入を検討 | 必要になった時点 |

### Cloudflare → Cloud Run の接続方式

| 方式 | 概要 | 長所 | 短所 |
| --- | --- | --- | --- |
| A. Cloud Run ドメインマッピング | Cloudflare のプロキシ CNAME を `ghs.googlehosted.com` に向ける | 追加費用なし．構成が単純 | 対応リージョン・提供状態の確認が必要．証明書発行時にプロキシとの相性確認が必要．`run.app` URL から WAF を迂回できる |
| B. 外部アプリケーション LB + サーバーレス NEG | Cloudflare → LB → Cloud Run．Cloud Run の ingress を LB 経由に限定 | WAF の迂回を防げる．Cloud Armor も使える | LB の固定費が発生．リソース数が増える |
| C. Cloudflare Workers で転送 | Worker が `run.app` URL へリクエストを転送 | 低コスト | Worker のコード管理が必要．`run.app` URL から WAF を迂回できる |

A・C を採用する場合は，Cloud Run のデフォルト URL 無効化や，Cloudflare 経由であることを API で検証する仕組みで迂回を防げるか検証する．

## 6. ローカル環境の注意

- Terraform CLI，`gcloud` CLI が必要．GCP の認証は `gcloud auth application-default login`，Cloudflare は `CLOUDFLARE_API_TOKEN` を環境変数で渡す．
- `.terraform/`，`*.tfstate`，`*.tfstate.*`，`tfplan`，秘密を含む `*.secret.tfvars` はコミットしない（実装時に `.gitignore` へ追加する）．
- 本書の更新・`terraform plan` ではクラウドリソースを作成しない．`apply` は課金が発生しうるため，対象環境と plan を確認してから実行する．
