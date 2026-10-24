output "api_url" {
  description = "クライアントが接続する API の URL"
  value       = "https://${cloudflare_workers_custom_domain.api.hostname}"
}

output "worker_name" {
  description = "転送用 Worker の名前"
  value       = cloudflare_workers_script.proxy.script_name
}
