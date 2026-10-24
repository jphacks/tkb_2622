variable "account_id" {
  description = "Cloudflare アカウント ID"
  type        = string
}

variable "env" {
  description = "環境名（dev / prod）"
  type        = string
}

variable "origin_url" {
  description = "転送先の Cloud Run URL（https://...run.app）"
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+$", var.origin_url))
    error_message = "origin_url は末尾スラッシュなしの https URL を指定する．"
  }
}

variable "hostname" {
  description = "カスタムドメインで公開する場合のホスト名（例: api.example.com）．null なら workers.dev で公開する"
  type        = string
  default     = null

  validation {
    condition     = var.hostname == null || var.zone_id != null
    error_message = "hostname を指定する場合は zone_id も指定する．"
  }
}

variable "zone_id" {
  description = "hostname を置く Cloudflare ゾーン ID．workers.dev で公開する場合は不要"
  type        = string
  default     = null
}

variable "workers_dev_subdomain" {
  description = "アカウントの workers.dev サブドメイン名（<name>.workers.dev の <name>）．workers.dev で公開する場合に必須"
  type        = string
  default     = null

  validation {
    condition     = var.hostname != null || var.workers_dev_subdomain != null
    error_message = "hostname を指定しない場合は workers_dev_subdomain を指定する．"
  }
}
