terraform {
  required_version = "~> 1.14"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
