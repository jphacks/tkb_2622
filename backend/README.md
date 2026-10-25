# バックエンド

Go / `net/http`でHTTPとConnect互換のヘルスチェック，identityモジュールのRPC（業務User登録・端末登録）を提供する最小構成です．DBはPostgreSQL（Supabase PostgreSQLを想定）で，スキーマはgooseで管理します．Supabase AuthのアクセストークンをJWKSで検証します．識別以外の業務RPC・テストコードは未実装です．

今後の業務実装は，6つの業務モジュールと横断処理のworkflowからなるモジュラーモノリスとし，各モジュール内でクリーンアーキテクチャの依存方向を守ります．目標のディレクトリ構成・責務・トランザクション境界は[バックエンド構成](../docs/spec/1.バックエンド構成.md)を参照してください．以下は現在実装済みの構成と起動手順です．

## 採用方針と移行状況

構成は**Supabase Auth + Supabase PostgreSQL**です．[認証構成](../docs/spec/6.認証構成.md)と[インフラ構成](../docs/spec/2.インフラ構成.md)を参照してください．接続処理・マイグレーション・sqlc・ローカルComposeはPostgreSQL向けに移行済みです．Supabaseプロジェクトでの実接続とCloud Runへのデプロイは未検証です．

## ローカル起動

Docker Engine，Docker Compose v2，makeが必要です．ホストへのGoやDBのインストールは不要です．APIの起動にはSupabase Authのissuerが必要なため，`backend/.env.example`を`backend/.env`にコピーし，`SUPABASE_JWT_ISSUER`を設定します（ComposeがAPIコンテナへ渡します）．リポジトリルートから実行します．

```bash
make -C backend up
curl --fail http://localhost:8080/healthz
curl --fail http://localhost:8080/grpc.health.v1.Health/Check \
  -H 'Content-Type: application/json' \
  -H 'Connect-Protocol-Version: 1' \
  -d '{"service":""}'
```

HTTPは `{"status":"ok"}`，Connectは `{"status":"SERVING_STATUS_SERVING"}` を返します．両方ともAPIプロセスの生存確認であり，DB接続・スキーマの確認は行いません．APIは起動時にDBへ接続し，接続できない場合は起動しません．

`Makefile`は常に`compose.local.yaml`を指定します．`up`はビルド，PostgreSQLコンテナの起動，マイグレーション，API起動の順に実行します．マイグレーションが失敗した場合はAPIを起動しません．ローカル開発用APIは既定で `0.0.0.0:8080` に公開し，同じLANの実機iPhoneから接続できます．アプリのConnect API URLには `http://<MacのLAN IPv4>:8080` を設定します．MacのIPv4は `ipconfig getifaddr en0` で確認します．loopbackだけに限定する場合は `API_BIND_ADDRESS=127.0.0.1 make -C backend up` とします．

```sh
make -C backend up
```


| コマンド | 動作 |
| --- | --- |
| `make -C backend up` | ビルド・マイグレーション後にバックグラウンド起動 |
| `make -C backend down` | コンテナ・ネットワークを停止・削除．DBボリュームは保持 |
| `make -C backend logs` | ログを継続表示 |
| `make -C backend build` | イメージをビルド |
| `make -C backend migrate-up` | ローカルDBへ未適用マイグレーションを適用 |
| `make -C backend migrate-status` | ローカルDBの適用状態を表示 |
| `SEED_AUTH_SUBJECT=<UUID> make -C backend seed` | 登録済みiOS開発ユーザー用のモックデータをローカルDBへ投入 |
| `SEED_AUTH_SUBJECT=<UUID> make -C backend seed-group-profile` | アカウント設定を変えず，2人のプロフィールとグループだけを投入 |
| `make -C backend generate` | protoからGoコードと`internal/docs/openapi.yaml`を再生成．プラグインは`bin/`に配置 |

### 報酬設定の確認

報酬設定の回帰確認は，`backend`内で`go test ./internal/reward/... ./internal/workflow/...`を実行します。`WORKFLOW_TEST_DATABASE_URL`にマイグレーション済みローカルDBの接続URLを設定すると，workflow経由のセッション開始・初期残高・1分後の報酬付与も検証します。接続先はloopbackに限定し，作成した一時セッションはロールバック，一時ユーザー等は後処理で削除します。

### 開発用モックデータ

アプリでSupabase Authへログインし，業務UserとiOS端末を登録した後に実行します。`SEED_AUTH_SUBJECT`にはログインしたSupabaseユーザーのUUIDを指定してください。投入先は`compose.local.yaml`で起動するローカルPostgreSQLに固定されています。

```sh
SEED_AUTH_SUBJECT="<SupabaseユーザーUUID>" make -C backend seed
```

作業タスク，作業中の一時停止セッション，終了・中止済み履歴，報酬台帳と残高，iOS制限状態，2人分のグループを投入します。グループ用のfixtureメンバーには表示名「こむぎ」とアイコン`puppy`を設定し，ログイン中の利用者は自分のプロフィールアイコンで表示します。固定IDを使うため繰り返し実行できます。実データとの混在を避けるため，既存の別セッション・履歴・残高があるアカウントでは処理を中止し，何も変更しません。専用の開発用アカウントで実行してください。Screen Timeの許可・Shield表示や通知許可など，iOS端末内の状態はこのseedでは変更しません。

すでに利用中の開発アカウントでプロフィールとグループだけを確認する場合は，次のコマンドを使います。このfixtureはローカルCompose DB専用で，フォーカス・報酬・制限データを書き換えません。

```sh
SEED_AUTH_SUBJECT="<SupabaseユーザーUUID>" make -C backend seed-group-profile
```

ローカルのPostgreSQL（`postgres:17.7-bookworm`）は名前付きボリューム`tkb-backend-local_postgres-data`に保存します．通常の停止・再起動では消えません．マイグレーションを再実行しても適用済みの変更は繰り返しません．

ローカルDBは2つのロールを使い分けます．マイグレーションは`postgres`ロール，APIは`dev/postgres/001_roles.sql`で作る`tkb_app`ロール（`app`スキーマのテーブルへのSELECT／INSERT／UPDATE／DELETEのみ）で接続します．初期化SQLはボリューム作成時にだけ実行されるため，変更した場合はボリュームを作り直します．これらのパスワードはローカル専用です．

DBクライアント（DBeaver等）からは`localhost:5432`，データベース`tkb`で接続できます．PostgreSQLはホストの`127.0.0.1`だけに公開しています．全テーブルを見る場合は`postgres`／`local-migration-only`，APIと同じ権限で確認する場合は`tkb_app`／`local-app-only`を使います．業務テーブルは`app`スキーマにあります．ホストで別のPostgreSQLが5432番を使っている場合は起動に失敗するため，停止するか`compose.local.yaml`の公開ポートを変更してください．

旧SQLite用のボリューム`tkb-backend-local_sqlite-data`は自動では削除しません．不要なら`docker volume rm tkb-backend-local_sqlite-data`で削除してください．

## APIドキュメント（Swagger UI）

ローカル起動後，ブラウザで <http://localhost:8080/docs> を開くとRPCの一覧を確認・実行できます．仕様は`internal/docs/openapi.yaml`で，`make -C backend generate`がprotoから生成します．proto変更後は再生成してから`make -C backend up`で再ビルドしてください．

RPCはSupabaseのアクセストークンが必要です．画面右上の「Authorize」にトークン（`Bearer`は不要）を入力してから「Try it out」で実行します．`/docs`は`API_DOCS_ENABLED=true`のときだけ公開し，`compose.local.yaml`でのみ有効にしています．

## 構成と環境変数

- `cmd/api`：HTTPサーバー，JSON形式のslogログ，Connect RPCごとのHTTP method／path／status／所要時間記録，SIGINT／SIGTERMでの正常終了．request bodyとAuthorization headerはログに記録しない．
- `cmd/migrate`：`up`／`down`／`status`コマンド．SQLはバイナリに埋め込みます．
- `internal/server`：HTTP，Connectハンドラー，公式`connectrpc.com/grpchealth`のハンドラー．
- `internal/database`：pgx（`database/sql`互換）によるPostgreSQL接続．Supabaseのトランザクションプーラーと両立するよう，サーバー側のprepared statementを使いません．
- `internal/identity`：業務User・端末のdomain／application／adapter（Connect・JWT検証・sqlcによる永続化）．
- `migrations/postgres`：`app`スキーマのDDLとgooseの適用履歴．

| 環境変数 | 用途・既定値 |
| --- | --- |
| `PORT` | APIの待受ポート．既定8080 |
| `DATABASE_URL` | APIで必須．API実行用ロールのPostgreSQL接続URL．クラウドでは`sslmode=require`以上を指定 |
| `DB_MAX_CONNECTIONS` | インスタンスあたりの最大DB接続数．既定5，1〜100 |
| `MIGRATION_DATABASE_URL` | `migrate`で必須．DDLを適用できるロールのPostgreSQL接続URL |
| `SUPABASE_JWT_ISSUER` | APIで必須．Supabase Authのissuer（`https://<project>.supabase.co/auth/v1`）．JWKSの取得先もここから決まる |
| `SUPABASE_JWT_AUDIENCE` | 許可するaudience．既定`authenticated` |
| `AUTH_ALLOW_LOCAL_HTTP` | `true`でHTTPのissuer（Supabase CLIのローカル環境等）を許可．既定は無効 |
| `API_DOCS_ENABLED` | `true`で`/docs`（Swagger UI）を公開．既定は無効．ローカルComposeでは有効 |
| `APP_ENV`，`REWARD_POLICY_TEST_MODE` | ローカルCompose専用．`local`と`true`の組合せで新規セッションのみ作業1分ごとに報酬20秒を付与し，既知活動の最低条件を1分にする．アカウントごとに初回の試験セッションで1分を一度だけ付与する．本番へ設定しない |
| `APNS_TEAM_ID`，`APNS_KEY_ID`，`APNS_BUNDLE_ID`，`APNS_AUTH_KEY_PATH` | すべて設定するとAPNs配信を有効化．秘密鍵ファイルは実行環境のSecret管理からマウントする．未設定時はAPNs送信を停止し，Outboxを保持 |
| `BACKEND_IMAGE` | デプロイ用Composeで必須．Artifact Registryの固定タグまたはダイジェスト付きイメージ |

接続先や認証情報をログへ出力しないよう，DBエラーは秘匿したメッセージに変換します．`.env`はコードから自動読み込みしません．必要な変数を実行環境から渡してください．

ローカルでAPNsを有効にする場合は、`backend/.env`へ`APNS_TEAM_ID`、`APNS_KEY_ID`、`APNS_BUNDLE_ID`、`APNS_AUTH_KEY_FILE`を設定します。`APNS_AUTH_KEY_FILE`には`.p8`ファイルの絶対パスを指定し、ファイルはリポジトリ外に保管してください。ComposeはそのファイルをAPIコンテナへ読み取り専用でマウントします。未設定の場合は通知送信を無効のまま起動します。

## DBスキーマ

業務テーブルは非公開の`app`スキーマに置き，`PUBLIC`の権限を取り消しています．Supabase管理の`auth`スキーマはgooseの管理対象にしません．

| テーブル | 内容 |
| --- | --- |
| `app.users` | 業務User．`id`（UUID），`auth_provider`（`supabase`のみ），`auth_subject`（Supabase AuthのユーザーID），公開表示名，プロフィール画像カタログID．プロバイダーとsubjectの組み合わせは一意．状態は`ACTIVE`／`DISABLED` |
| `app.devices` | 登録端末．プラットフォームは`MACOS`／`WINDOWS`／`IOS`．有効なiPhoneはUserごとに1台 |
| `app.notification_endpoints` | 有効なiPhone端末ごとのAPNs tokenとSandbox／Production環境 |
| `app.notification_outbox` | グループ作業開始通知の宛先・送信状態・再試行記録 |
| `app.identity_operations` | 再送を同じ結果で返すための操作記録 |

作業開始イベントとOutboxは同じPostgreSQLトランザクションで保存します。ローカルAPIは30秒間隔で保留通知を再試行します。本番のCloud Runではプロセス内workerの継続を保証しないため、永続的な再試行にはCloud Scheduler／Cloud Tasks等を接続してください。APNsは`APNS_TEAM_ID`、`APNS_KEY_ID`、アプリのbundle ID、Apple Push Auth Keyが必要です。秘密鍵をソースや通常の環境変数値へ保存せず、Secret Manager等からファイルとしてマウントしてください。

通常起動でDownは実行しません．`migrate down`は業務テーブルとそのデータを削除するため，明示的なロールバック用です．

## Cloud Run向けの準備と実行手順

Cloud Runのサービス（`tkb-<env>-api`）・マイグレーション用Job（`tkb-<env>-migrate`）・Artifact Registry・Secretは[infra](../infra/README.md)のTerraformで作成します．環境変数とSecretの参照もTerraformで設定するため，デプロイではイメージだけを更新します．Supabase上ではAPI実行用ロールを作成し，`app`スキーマへの必要な権限だけを付与します（[インフラ構成](../docs/spec/2.インフラ構成.md)）．mainへのマージでGitHub Actions（`.github/workflows/deploy-backend.yml`）がdevに対して同じ手順を実行します．以下は手動で実行する場合の手順です．

1. `ENV`（`dev`／`prod`），`PROJECT_ID`，`REGION`（`asia-northeast1`）を設定し，リポジトリルートでイメージをビルド・公開します．タグはコミットIDなどの固定値にします．

```bash
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/tkb/backend:$(git rev-parse --short HEAD)"
gcloud auth configure-docker "$REGION-docker.pkg.dev"
docker build --platform linux/amd64 -t "$IMAGE" backend
docker push "$IMAGE"
```

2. マイグレーションJobのイメージを更新して実行します．Jobは並列数1で，失敗しても再試行しません．

```bash
gcloud run jobs update "tkb-$ENV-migrate" --image "$IMAGE" --project "$PROJECT_ID" --region "$REGION"
gcloud run jobs execute "tkb-$ENV-migrate" --wait --project "$PROJECT_ID" --region "$REGION"
```

3. マイグレーション成功後，APIを同じイメージで更新します．

```bash
gcloud run deploy "tkb-$ENV-api" --image "$IMAGE" --project "$PROJECT_ID" --region "$REGION"
```

`gcloud run deploy`には`--image`以外の設定を渡しません．環境変数・スケール等を変える場合はTerraformを変更します．`compose.deploy.yaml`（`gcloud run compose up`）は別のサービスを作成するため，Terraform管理の環境では使いません．Supabase実接続とCloud Run実行は接続情報の用意後に検証します．

## 開発時の確認と今後の拡張

Go 1.26.8を使用します．依存バージョンは`go.mod`／`go.sum`で固定します．

```bash
go test ./...
go build ./...
go vet ./...
docker compose -f compose.local.yaml config --quiet
```

ローカルで起動とヘルスチェックを確認できます．DB状態は`make migrate-status`で確認します．

SQLは`migrations/postgres`のgoose SQLをスキーマの正本として，sqlc（`sqlc.yaml`，PostgreSQLエンジン）でGoコードを生成します．APIはProtocol Buffers / BufでConnectのRPCを定義・生成します（`make -C backend generate`）．業務機能の追加時も同じ流れでモジュールごとに追加します．
