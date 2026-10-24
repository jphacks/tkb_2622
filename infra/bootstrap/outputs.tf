output "state_bucket" {
  description = "tfstate 用バケット名．envs/backend.hcl に設定する"
  value       = google_storage_bucket.tfstate.name
}
