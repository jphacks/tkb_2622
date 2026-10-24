data "terraform_remote_state" "gcp" {
  backend = "gcs"

  config = {
    bucket = var.state_bucket
    prefix = "envs/dev/gcp"
  }
}

module "api_endpoint" {
  source = "../../../modules/cloudflare/api-endpoint"

  account_id = var.account_id
  zone_id    = var.zone_id
  env        = "dev"
  hostname   = var.hostname
  origin_url = data.terraform_remote_state.gcp.outputs.service_uri
}
