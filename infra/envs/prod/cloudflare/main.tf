data "terraform_remote_state" "gcp" {
  backend = "gcs"

  config = {
    bucket = var.state_bucket
    prefix = "envs/prod/gcp"
  }
}

module "api_endpoint" {
  source = "../../../modules/cloudflare/api-endpoint"

  account_id = var.account_id
  env        = "prod"
  origin_url = data.terraform_remote_state.gcp.outputs.service_uri

  # hostname を指定しなければ workers.dev で公開する
  workers_dev_subdomain = var.workers_dev_subdomain
  hostname              = var.hostname
  zone_id               = var.zone_id
}
