data "terraform_remote_state" "shared_gcp" {
  backend = "gcs"

  config = {
    bucket = var.state_bucket
    prefix = "envs/shared/gcp"
  }
}

module "api" {
  source = "../../../modules/gcp/cloud-run-api"

  project_id = var.project_id
  region     = var.region
  env        = "prod"

  supabase_jwt_issuer = var.supabase_jwt_issuer
  db_max_connections  = var.db_max_connections
  min_instances       = var.min_instances
  max_instances       = var.max_instances
  deletion_protection = var.deletion_protection

  origin_auth_token_version = var.origin_auth_token_version

  deployer_service_account_email = data.terraform_remote_state.shared_gcp.outputs.deployer_service_account_email
}
