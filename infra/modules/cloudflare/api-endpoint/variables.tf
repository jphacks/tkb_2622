variable "account_id" {
  description = "Cloudflare アカウント ID"
  type        = string
}

variable "env" {
  description = "環境名（dev / prod）"
  type        = string
}

variable "workers_dev_subdomain" {
  description = "アカウントの workers.dev サブドメイン名（<name>.workers.dev の <name>）"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.workers_dev_subdomain))
    error_message = "workers_dev_subdomain は <name>.workers.dev の <name> 部分だけを指定する．"
  }
}

variable "origin_url" {
  description = "転送先の Cloud Run URL（https://...run.app）"
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+$", var.origin_url))
    error_message = "origin_url は末尾スラッシュなしの https URL を指定する．"
  }
}

variable "origin_auth_token" {
  description = "Cloud Run への転送時に X-Origin-Auth ヘッダーで付与する共有シークレット"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.origin_auth_token) >= 32
    error_message = "origin_auth_token は32文字以上にする．"
  }
}

variable "rate_limit_namespace_id" {
  description = "レート制限のカウンターを分ける ID（アカウント内で環境ごとに一意な整数の文字列）"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.rate_limit_namespace_id))
    error_message = "rate_limit_namespace_id は整数の文字列にする．"
  }
}

variable "rate_limit_requests" {
  description = "1つの IP から rate_limit_period 秒の間に許可するリクエスト数"
  type        = number
  default     = 120
}

variable "rate_limit_period" {
  description = "レート制限の集計期間（秒）．Workers の制約で 10 か 60 のみ"
  type        = number
  default     = 60

  validation {
    condition     = contains([10, 60], var.rate_limit_period)
    error_message = "rate_limit_period は 10 か 60 にする．"
  }
}
