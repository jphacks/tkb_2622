locals {
  script_name = "tkb-${var.env}-api-proxy"
}

# API ホスト名へのリクエストを Cloud Run の run.app URL へ転送する Worker
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

# ホスト名を Worker に割り当てる．DNS レコードと証明書は Cloudflare が自動で作成する．
resource "cloudflare_workers_custom_domain" "api" {
  account_id = var.account_id
  zone_id    = var.zone_id
  hostname   = var.hostname
  service    = cloudflare_workers_script.proxy.script_name
}
