# バックエンド

Go / `net/http`でHTTPとConnect互換のヘルスチェックを提供する最小構成です．Userテーブルをgooseで管理します．UserのCRUD・認証・業務RPC・テストコードは未実装です．

## ローカル起動

Docker Engine，Docker Compose v2，makeが必要です．ホストへのGoやDBのインストールは不要です．リポジトリルートから実行します．

```bash
make -C backend up
curl --fail http://localhost:8080/healthz
curl --fail http://localhost:8080/grpc.health.v1.Health/Check \
  -H 'Content-Type: application/json' \
  -H 'Connect-Protocol-Version: 1' \
  -d '{"service":""}'
```

HTTPは `{"status":"ok"}`，Connectは `{"status":"SERVING_STATUS_SERVING"}` を返します．両方ともAPIプロセスの生存確認であり，DB接続・スキーマの確認は行いません．業務APIがないため，APIプロセスはDB接続を開始せず，現在のDB接続処理はマイグレーション用です．

`Makefile`は常に`compose.local.yaml`を指定します．`up`はビルド，SQLiteへのマイグレーション，API起動の順に実行します．マイグレーションが失敗した場合はAPIを起動しません．APIは `127.0.0.1:8080` に公開します．

| コマンド | 動作 |
| --- | --- |
| `make -C backend up` | ビルド・マイグレーション後にバックグラウンド起動 |
| `make -C backend down` | コンテナ・ネットワークを停止・削除．DBボリュームは保持 |
| `make -C backend logs` | ログを継続表示 |
| `make -C backend build` | イメージをビルド |
| `make -C backend migrate-up` | ローカルDBへ未適用マイグレーションを適用 |
| `make -C backend migrate-status` | ローカルDBの適用状態を表示 |

SQLiteは名前付きボリューム`tkb-backend-local_sqlite-data`の`/data/app.db`に保存します．通常の停止・再起動では消えません．マイグレーションを再実行しても適用済みの変更は繰り返しません．

## 構成と環境変数

- `cmd/api`：HTTPサーバー，JSON形式のslogログ，SIGINT／SIGTERMでの正常終了．
- `cmd/migrate`：`up`／`down`／`status`コマンド．SQLはバイナリに埋め込みます．
- `internal/server`：HTTPと公式`connectrpc.com/grpchealth`のハンドラー．
- `internal/database`：ローカルSQLite（modernc）とリモートTurso/libSQL（libsql-client-go）の接続．
- `migrations`：UserのDDLとgooseの適用履歴．

| 環境変数 | 用途・既定値 |
| --- | --- |
| `PORT` | APIの待受ポート．既定8080 |
| `DB_DRIVER` | マイグレーションの接続方式．`sqlite`（既定）または`libsql` |
| `SQLITE_PATH` | SQLiteのファイルパス．既定`app.db`，ローカルComposeでは`/data/app.db` |
| `TURSO_DATABASE_URL` | libSQL互換Turso DBの`libsql://`または`https://` URL |
| `TURSO_AUTH_TOKEN` | libSQL接続時に必須の認証トークン |
| `BACKEND_IMAGE` | デプロイ用Composeで必須．Artifact Registryの固定タグまたはダイジェスト付きイメージ |

Tursoは今回libSQL互換DBを対象とします．Tursoの別エンジンへの接続ドライバーは含みません．接続先や認証トークンをログへ出力しないよう，DBエラーは秘匿したメッセージに変換します．`.env`はコードから自動読み込みしません．必要な変数を実行環境から渡してください．

## Userテーブル

`users`は`id`（TEXT主キー，NOT NULL），`auth_provider`，`auth_subject`，`created_at`（UTC文字列），`status`を持ちます．全列NOT NULL，認証プロバイダーとsubjectの組み合わせは一意です．状態は`ACTIVE`（既定）／`DISABLED`に限定します．IDは将来アプリ側で生成するUUIDを保存する想定で，今回ID生成・登録処理はありません．

gooseの管理テーブルを除き，業務テーブルは`users`のみです．通常起動でDownは実行しません．`migrate down`はUserテーブルとそのデータを削除するため，明示的なロールバック用です．

## Cloud Run向けの準備と実行手順

`compose.deploy.yaml`はCloud RunのComposeデプロイ用です．ローカルDB・ボリューム・起動時マイグレーションを含みません．[Cloud Run公式手順](https://docs.cloud.google.com/run/docs/deploy-run-compose)に従い，Google Cloudプロジェクト，Artifact Registry，TursoのlibSQL互換DBと接続情報を事前に用意します．以下は実行手順であり，この変更ではクラウドへのデプロイを行っていません．

1. `backend/`へ移動し，`BACKEND_IMAGE`にArtifact Registryのイメージ名と固定タグを設定します．Google Cloud・レジストリへの認証も済ませます．
2. 同じイメージをビルド・公開します．

```bash
docker build --platform linux/amd64 -t "$BACKEND_IMAGE" .
docker push "$BACKEND_IMAGE"
```

3. `TURSO_DATABASE_URL`と`TURSO_AUTH_TOKEN`を環境変数に設定し，デプロイ前に一度だけマイグレーションします．複数のデプロイから並行実行しないでください．

```bash
docker run --rm \
  -e DB_DRIVER=libsql \
  -e TURSO_DATABASE_URL \
  -e TURSO_AUTH_TOKEN \
  "$BACKEND_IMAGE" /app/migrate up
```

4. マイグレーション成功後，同じイメージをデプロイします．`PROJECT_ID`と`REGION`は対象環境の値を設定します．

```bash
gcloud run compose up compose.deploy.yaml --project "$PROJECT_ID" --region "$REGION"
```

環境変数はCompose経由でCloud Runへ渡します．トークンをファイルやリポジトリに書き込まず，値を展開する`docker compose config`の出力も共有しないでください．Cloud Runへのアクセス認証は別途設定し，本構成では公開アクセスを自動で有効化しません．Turso実接続とCloud Run実行は接続情報の提供後に検証します．

## 開発時の確認と今後の拡張

Go 1.26.8を使用します．依存バージョンは`go.mod`／`go.sum`で固定します．

```bash
go build ./...
go vet ./...
docker compose -f compose.local.yaml config --quiet
```

テストコードは今回追加していません．ローカルで起動とヘルスチェックを確認できます．DB状態は`make migrate-status`で確認します．

現段階では業務SQLや独自RPCがないため，sqlc・Bufの設定と生成コードは追加しません．業務機能の追加時に，既存のgoose SQLをスキーマの正本としてsqlcを導入し，Protocol Buffers / BufでConnectの業務APIを定義・生成します．
