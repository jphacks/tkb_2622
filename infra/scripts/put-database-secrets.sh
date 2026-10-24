#!/usr/bin/env bash
# Supabase の接続情報から DATABASE_URL / MIGRATION_DATABASE_URL を組み立て，Secret Manager に登録する．
#   使い方: infra/scripts/put-database-secrets.sh <env> <gcp_project_id> <supabase_project_ref> <pooler_host>
#   例:     infra/scripts/put-database-secrets.sh dev tkb-2622-dev fxkteukzzvyftpcllrkn aws-0-ap-northeast-1.pooler.supabase.com
# パスワードは実行時に入力する（画面・シェル履歴・ファイルに残さない）．記号は URL エンコードする．
#   MIGRATION_DATABASE_URL: postgres ロール，Session pooler（5432）
#   DATABASE_URL:           tkb_app ロール， Transaction pooler（6543）
# Docker があれば，登録前に両方の URL で実際に接続できるか確認する．
set -euo pipefail

if [[ $# -ne 4 ]]; then
	sed -n '2,4p' "$0" >&2
	exit 2
fi
env_name=$1 project=$2 ref=$3 host=$4

if [[ "$env_name" != dev && "$env_name" != prod ]]; then
	echo "env は dev か prod を指定してください: $env_name" >&2
	exit 2
fi
if [[ ! "$host" =~ ^aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com$ ]]; then
	echo "pooler のホストは aws-<番号>-<リージョン>.pooler.supabase.com の形で指定してください: $host" >&2
	exit 2
fi

database_secret="tkb-$env_name-database-url"
migration_secret="tkb-$env_name-migration-database-url"
for secret in "$database_secret" "$migration_secret"; do
	if ! gcloud secrets describe "$secret" --project "$project" >/dev/null 2>&1; then
		echo "Secret $secret がありません．先に次を実行してください:" >&2
		echo "  terraform -chdir=infra/envs/$env_name/gcp apply -target='module.api.google_secret_manager_secret.this'" >&2
		exit 1
	fi
done

read -rs -p "postgres のDBパスワード: " pg_pass; echo
read -rs -p "tkb_app のパスワード: " app_pass; echo
if [[ -z "$pg_pass" || -z "$app_pass" ]]; then
	echo "パスワードが空です．" >&2
	exit 1
fi

urlencode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""), end="")'; }
MIGRATION_DATABASE_URL="postgresql://postgres.$ref:$(printf '%s' "$pg_pass" | urlencode)@$host:5432/postgres?sslmode=require"
DATABASE_URL="postgresql://tkb_app.$ref:$(printf '%s' "$app_pass" | urlencode)@$host:6543/postgres?sslmode=require"
unset pg_pass app_pass
export DATABASE_URL MIGRATION_DATABASE_URL

# 登録前に接続を確認する．URL はコマンド引数ではなく環境変数で渡す
if command -v docker >/dev/null 2>&1; then
	for var in MIGRATION_DATABASE_URL DATABASE_URL; do
		echo "==> $var で接続を確認します"
		docker run --rm -e "$var" postgres:17.7-bookworm \
			sh -c "psql \"\$$var\" -Atqc 'select current_user'" ||
			{ echo "$var で接続できませんでした．パスワード・tkb_app ロールの作成・ホストを確認してください．" >&2; exit 1; }
	done
else
	echo "Docker がないため接続確認を省略します．"
fi

put_secret() {
	local secret=$1 value=$2 stored
	printf '%s' "$value" | gcloud secrets versions add "$secret" --data-file=- --project "$project"
	stored=$(gcloud secrets versions access latest --secret "$secret" --project "$project" | wc -c)
	if [[ "$stored" -ne ${#value} ]]; then
		echo "$secret に保存された長さ（$stored）が一致しません．" >&2
		exit 1
	fi
}
put_secret "$database_secret" "$DATABASE_URL"
put_secret "$migration_secret" "$MIGRATION_DATABASE_URL"
unset DATABASE_URL MIGRATION_DATABASE_URL
echo "登録しました: $database_secret, $migration_secret"
