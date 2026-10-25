data "terraform_remote_state" "gcp" {
  backend = "gcs"

  config = {
    bucket = var.state_bucket
    prefix = "envs/dev/gcp"
  }
}

# envs/dev/gcp が生成した迂回防止用シークレット．値はこのスタックの state に残る
data "google_secret_manager_secret_version" "origin_auth_token" {
  project = data.terraform_remote_state.gcp.outputs.project_id
  secret  = data.terraform_remote_state.gcp.outputs.origin_auth_token_secret_id
  version = data.terraform_remote_state.gcp.outputs.origin_auth_token_secret_version
}

module "api_endpoint" {
  source = "../../../modules/cloudflare/api-endpoint"

  account_id            = var.account_id
  env                   = "dev"
  workers_dev_subdomain = var.workers_dev_subdomain
  origin_url            = data.terraform_remote_state.gcp.outputs.service_uri
  origin_auth_token     = data.google_secret_manager_secret_version.origin_auth_token.secret_data

  # レート制限のカウンターは環境ごとに分ける
  rate_limit_namespace_id = "1001"
  rate_limit_requests     = var.rate_limit_requests
  rate_limit_period       = var.rate_limit_period
}
