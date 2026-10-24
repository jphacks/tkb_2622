output "service_name" {
  description = "Cloud Run サービス名"
  value       = google_cloud_run_v2_service.api.name
}

output "service_uri" {
  description = "Cloud Run のデフォルト URL（https://...run.app）．Cloudflare Worker の転送先"
  value       = google_cloud_run_v2_service.api.uri
}

output "migrate_job_name" {
  description = "マイグレーション用 Cloud Run Job 名"
  value       = google_cloud_run_v2_job.migrate.name
}

output "api_service_account_email" {
  description = "API 実行用 SA"
  value       = google_service_account.api.email
}

output "migrate_service_account_email" {
  description = "マイグレーション Job 用 SA"
  value       = google_service_account.migrate.email
}

output "secret_ids" {
  description = "値を投入する Secret の ID"
  value       = { for k, s in google_secret_manager_secret.this : k => s.secret_id }
}
