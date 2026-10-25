variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "Cloud Run のリージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "state_bucket" {
  description = "tfstate 用 GCS バケット名（envs/shared/gcp の出力を読む）"
  type        = string
}

variable "supabase_jwt_issuer" {
  description = "この環境の Supabase Auth issuer"
  type        = string
}

variable "min_instances" {
  description = "最小インスタンス数"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "最大インスタンス数"
  type        = number
  default     = 2
}

variable "db_max_connections" {
  description = "インスタンスあたりの最大 DB 接続数"
  type        = number
  default     = 5
}

variable "deletion_protection" {
  description = "Cloud Run サービス・Job の削除保護"
  type        = bool
  default     = true
}

variable "origin_auth_token_version" {
  description = "迂回防止用シークレットの版．上げると新しい値を生成し，envs/<env>/cloudflare の apply で Worker にも反映する"
  type        = number
  default     = 1
}
