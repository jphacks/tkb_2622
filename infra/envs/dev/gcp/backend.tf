terraform {
  backend "gcs" {
    prefix = "envs/dev/gcp"
  }
}
