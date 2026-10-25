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

output "origin_auth_token_secret_id" {
  description = "迂回防止用シークレットの Secret ID．envs/<env>/cloudflare が値を読む"
  value       = module.api.origin_auth_token_secret_id
}

output "origin_auth_token_secret_version" {
  description = "迂回防止用シークレットの版番号"
  value       = module.api.origin_auth_token_secret_version
}

output "project_id" {
  description = "GCP プロジェクト ID．envs/<env>/cloudflare が Secret を読むときに使う"
  value       = var.project_id
}
