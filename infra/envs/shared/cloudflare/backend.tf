terraform {
  backend "gcs" {
    prefix = "envs/shared/cloudflare"
  }
}
