# ゾーン全体に効く設定．dev/prod のホスト名で共有するため環境別 state に置かない．
locals {
  zone_settings = {
    ssl              = "strict"
    always_use_https = "on"
    min_tls_version  = "1.2"
    tls_1_3          = "on"
  }
}

resource "cloudflare_zone_setting" "this" {
  for_each = local.zone_settings

  zone_id    = var.zone_id
  setting_id = each.key
  value      = each.value
}
