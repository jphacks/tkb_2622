output "artifact_registry_repository_url" {
  description = "イメージの公開先（<url>/backend:<tag>）"
  value       = "${google_artifact_registry_repository.backend.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}"
}

output "deployer_service_account_email" {
  description = "GitHub Actions が借用する SA"
  value       = google_service_account.deployer.email
}

output "workload_identity_provider" {
  description = "google-github-actions/auth の workload_identity_provider に指定する値"
  value       = google_iam_workload_identity_pool_provider.github.name
}
