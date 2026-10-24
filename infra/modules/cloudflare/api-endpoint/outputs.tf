output "api_url" {
  description = "クライアントが接続する API の URL"
  value = (
    local.use_custom_domain
    ? "https://${var.hostname}"
    : "https://${cloudflare_workers_script.proxy.script_name}.${var.workers_dev_subdomain}.workers.dev"
  )
}

output "worker_name" {
  description = "転送用 Worker の名前"
  value       = cloudflare_workers_script.proxy.script_name
}
