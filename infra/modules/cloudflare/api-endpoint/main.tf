locals {
  script_name = "tkb-${var.env}-api-proxy"
}

# API へのリクエストを検査（許可リスト・レート制限）し，Cloud Run の run.app URL へ転送する Worker
resource "cloudflare_workers_script" "proxy" {
  account_id         = var.account_id
  script_name        = local.script_name
  content            = file("${path.module}/worker/proxy.js")
  main_module        = "proxy.js"
  compatibility_date = "2026-10-01"

  bindings = [
    {
      name = "ORIGIN_URL"
      type = "plain_text"
      text = var.origin_url
    },
    {
      # Cloud Run は X-Origin-Auth にこの値がないリクエストを拒否する（run.app への直接アクセス対策）
      name = "ORIGIN_AUTH_TOKEN"
      type = "secret_text"
      text = var.origin_auth_token
    },
    {
      # 429 応答の Retry-After に使う
      name = "RATE_LIMIT_PERIOD"
      type = "plain_text"
      text = tostring(var.rate_limit_period)
    },
    {
      # IP 単位のレート制限．ロケーションごとの近似値で，厳密な上限ではない
      name         = "RATE_LIMITER"
      type         = "ratelimit"
      namespace_id = var.rate_limit_namespace_id
      simple = {
        limit  = var.rate_limit_requests
        period = var.rate_limit_period
      }
    },
  ]

  # 遮断ログ（console.log）を Dashboard の Workers Logs で確認できるようにする
  observability = {
    enabled = true
  }
}

# https://<script_name>.<subdomain>.workers.dev で公開する．プレビュー用 URL は公開しない．
resource "cloudflare_workers_script_subdomain" "proxy" {
  account_id       = var.account_id
  script_name      = cloudflare_workers_script.proxy.script_name
  enabled          = true
  previews_enabled = false
}
