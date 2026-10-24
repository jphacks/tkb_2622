terraform {
  backend "gcs" {
    prefix = "envs/prod/gcp"
  }
}
