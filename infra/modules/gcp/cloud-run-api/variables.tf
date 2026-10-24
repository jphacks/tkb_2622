variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "Cloud Run のリージョン"
  type        = string
}

variable "env" {
  description = "環境名（dev / prod）．リソース名・ラベルに使う"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env は dev か prod を指定する．"
  }
}

variable "initial_image" {
  description = "作成時だけ使うコンテナイメージ．以降のイメージ更新は CI が行い，Terraform は差分を無視する"
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "supabase_jwt_issuer" {
  description = "Supabase Auth の issuer（https://<project>.supabase.co/auth/v1）"
  type        = string
}

variable "supabase_jwt_audience" {
  description = "許可する JWT audience"
  type        = string
  default     = "authenticated"
}

variable "db_max_connections" {
  description = "インスタンスあたりの最大 DB 接続数．max_instances との積が Supabase の接続上限を超えないようにする"
  type        = number
  default     = 5
}

variable "min_instances" {
  description = "最小インスタンス数．0 でアイドル時の課金をなくす"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "最大インスタンス数"
  type        = number
  default     = 2
}

variable "cpu" {
  description = "コンテナの CPU 上限"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "コンテナのメモリ上限"
  type        = string
  default     = "512Mi"
}

variable "deployer_service_account_email" {
  description = "イメージを更新する CI 用 SA．実行用 SA の actAs 権限を付与する．null なら付与しない"
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Cloud Run サービス・Job の削除保護"
  type        = bool
  default     = true
}

variable "origin_auth_token_version" {
  description = "迂回防止用シークレットの版．値を上げると新しいシークレットを生成して入れ替える"
  type        = number
  default     = 1
}
