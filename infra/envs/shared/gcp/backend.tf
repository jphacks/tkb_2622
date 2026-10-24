terraform {
  backend "gcs" {
    prefix = "envs/shared/gcp"
  }
}
