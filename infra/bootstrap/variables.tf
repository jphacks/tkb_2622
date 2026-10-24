variable "project_id" {
  description = "GCP プロジェクト ID．dev/prod で共用する"
  type        = string
}

variable "region" {
  description = "既定のリージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "state_bucket" {
  description = "全ルートモジュールの tfstate を保存する GCS バケット名．envs/backend.hcl の bucket と一致させる"
  type        = string
}
