variable "account_id" {
  description = "Cloudflare アカウント ID"
  type        = string
}

variable "workers_dev_subdomain" {
  description = "アカウントの workers.dev サブドメイン名（<name>.workers.dev の <name>）"
  type        = string
}

variable "state_bucket" {
  description = "tfstate 用 GCS バケット名（envs/<env>/gcp の出力を読む）"
  type        = string
}

variable "rate_limit_requests" {
  description = "1つの IP から rate_limit_period 秒の間に許可するリクエスト数"
  type        = number
  default     = 120
}

variable "rate_limit_period" {
  description = "レート制限の集計期間（秒）．10 か 60"
  type        = number
  default     = 60
}
