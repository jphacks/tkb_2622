output "service_name" {
  description = "Cloud Run サービス名"
  value       = module.api.service_name
}

output "service_uri" {
  description = "Cloud Run の URL．envs/<env>/cloudflare が転送先として読む"
  value       = module.api.service_uri
}

output "migrate_job_name" {
  description = "マイグレーション用 Cloud Run Job 名"
  value       = module.api.migrate_job_name
}

output "secret_ids" {
  description = "値を投入する Secret の ID"
  value       = module.api.secret_ids
}
