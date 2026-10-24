locals {
  script_name       = "tkb-${var.env}-api-proxy"
  use_custom_domain = var.hostname != null
}

# API へのリクエストを Cloud Run の run.app URL へ転送する Worker
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
  ]
}

# workers.dev での公開．カスタムドメインを使う場合は無効にし，公開経路を1つにする．
resource "cloudflare_workers_script_subdomain" "proxy" {
  account_id       = var.account_id
  script_name      = cloudflare_workers_script.proxy.script_name
  enabled          = !local.use_custom_domain
  previews_enabled = false
}

# カスタムドメインでの公開．DNS レコードと証明書は Cloudflare が自動で作成する．
resource "cloudflare_workers_custom_domain" "api" {
  count = local.use_custom_domain ? 1 : 0

  account_id = var.account_id
  zone_id    = var.zone_id
  hostname   = var.hostname
  service    = cloudflare_workers_script.proxy.script_name
}
