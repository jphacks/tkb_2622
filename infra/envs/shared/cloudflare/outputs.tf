output "zone_settings" {
  description = "適用したゾーン設定"
  value       = { for k, s in cloudflare_zone_setting.this : k => s.value }
}
