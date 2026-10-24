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

`Makefile`は常に`compose.local.yaml`を指定します．`up`はビルド，PostgreSQLコンテナの起動，マイグレーション，API起動の順に実行します．マイグレーションが失敗した場合はAPIを起動しません．APIは `127.0.0.1:8080` に公開します．

| コマンド | 動作 |
| --- | --- |
| `make -C backend up` | ビルド・マイグレーション後にバックグラウンド起動 |
| `make -C backend down` | コンテナ・ネットワークを停止・削除．DBボリュームは保持 |
| `make -C backend logs` | ログを継続表示 |
| `make -C backend build` | イメージをビルド |
| `make -C backend migrate-up` | ローカルDBへ未適用マイグレーションを適用 |
| `make -C backend migrate-status` | ローカルDBの適用状態を表示 |
| `make -C backend generate` | protoからGoコードと`internal/docs/openapi.yaml`を再生成．プラグインは`bin/`に配置 |

ローカルのPostgreSQL（`postgres:17.7-bookworm`）は名前付きボリューム`tkb-backend-local_postgres-data`に保存します．通常の停止・再起動では消えません．マイグレーションを再実行しても適用済みの変更は繰り返しません．

ローカルDBは2つのロールを使い分けます．マイグレーションは`postgres`ロール，APIは`dev/postgres/001_roles.sql`で作る`tkb_app`ロール（`app`スキーマのテーブルへのSELECT／INSERT／UPDATE／DELETEのみ）で接続します．初期化SQLはボリューム作成時にだけ実行されるため，変更した場合はボリュームを作り直します．これらのパスワードはローカル専用です．

旧SQLite用のボリューム`tkb-backend-local_sqlite-data`は自動では削除しません．不要なら`docker volume rm tkb-backend-local_sqlite-data`で削除してください．

## APIドキュメント（Swagger UI）

ローカル起動後，ブラウザで <http://localhost:8080/docs> を開くとRPCの一覧を確認・実行できます．仕様は`internal/docs/openapi.yaml`で，`make -C backend generate`がprotoから生成します．proto変更後は再生成してから`make -C backend up`で再ビルドしてください．

RPCはSupabaseのアクセストークンが必要です．画面右上の「Authorize」にトークン（`Bearer`は不要）を入力してから「Try it out」で実行します．`/docs`は`API_DOCS_ENABLED=true`のときだけ公開し，`compose.local.yaml`でのみ有効にしています．

## 構成と環境変数

- `cmd/api`：HTTPサーバー，JSON形式のslogログ，SIGINT／SIGTERMでの正常終了．
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
| `BACKEND_IMAGE` | デプロイ用Composeで必須．Artifact Registryの固定タグまたはダイジェスト付きイメージ |

接続先や認証情報をログへ出力しないよう，DBエラーは秘匿したメッセージに変換します．`.env`はコードから自動読み込みしません．必要な変数を実行環境から渡してください．

## DBスキーマ

業務テーブルは非公開の`app`スキーマに置き，`PUBLIC`の権限を取り消しています．Supabase管理の`auth`スキーマはgooseの管理対象にしません．

| テーブル | 内容 |
| --- | --- |
| `app.users` | 業務User．`id`（UUID），`auth_provider`（`supabase`のみ），`auth_subject`（Supabase AuthのユーザーID）．プロバイダーとsubjectの組み合わせは一意．状態は`ACTIVE`／`DISABLED` |
| `app.devices` | 登録端末．プラットフォームは`MACOS`／`WINDOWS`／`IOS`．有効なiPhoneはUserごとに1台 |
| `app.identity_operations` | 再送を同じ結果で返すための操作記録 |

通常起動でDownは実行しません．`migrate down`は業務テーブルとそのデータを削除するため，明示的なロールバック用です．

## Cloud Run向けの準備と実行手順

`compose.deploy.yaml`はCloud RunのComposeデプロイ用です．ローカルDB・ボリューム・起動時マイグレーションを含みません．[Cloud Run公式手順](https://docs.cloud.google.com/run/docs/deploy-run-compose)に従い，Google Cloudプロジェクト，Artifact Registry，Supabaseプロジェクトと接続情報を事前に用意します．Supabase上ではAPI実行用ロールを作成し，`app`スキーマへの必要な権限だけを付与します（[インフラ構成](../docs/spec/2.インフラ構成.md)）．クラウドリソースは今後[infra](../infra/README.md)のTerraformで管理する予定です．以下は実行手順であり，この変更ではクラウドへのデプロイを行っていません．

1. `backend/`へ移動し，`BACKEND_IMAGE`にArtifact Registryのイメージ名と固定タグを設定します．Google Cloud・レジストリへの認証も済ませます．
2. 同じイメージをビルド・公開します．

```bash
docker build --platform linux/amd64 -t "$BACKEND_IMAGE" .
docker push "$BACKEND_IMAGE"
```

3. `MIGRATION_DATABASE_URL`にSupabaseの直接接続（IPv4環境ではセッションプーラー）のURLを設定し，デプロイ前に一度だけマイグレーションします．複数のデプロイから並行実行しないでください．

```bash
docker run --rm \
  -e MIGRATION_DATABASE_URL \
  "$BACKEND_IMAGE" /app/migrate up
```

4. マイグレーション成功後，`DATABASE_URL`（API実行用ロール．トランザクションプーラーが第一候補）と`SUPABASE_JWT_ISSUER`を設定し，同じイメージをデプロイします．`PROJECT_ID`と`REGION`は対象環境の値を設定します．

```bash
gcloud run compose up compose.deploy.yaml --project "$PROJECT_ID" --region "$REGION"
```

環境変数はCompose経由でCloud Runへ渡します．トークンをファイルやリポジトリに書き込まず，値を展開する`docker compose config`の出力も共有しないでください．Cloud Runへのアクセス認証は別途設定し，本構成では公開アクセスを自動で有効化しません．Supabase実接続とCloud Run実行は接続情報の用意後に検証します．

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
