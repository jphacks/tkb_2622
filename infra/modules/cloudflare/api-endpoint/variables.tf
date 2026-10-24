variable "account_id" {
  description = "Cloudflare アカウント ID"
  type        = string
}

variable "zone_id" {
  description = "API ホスト名を置く Cloudflare ゾーン ID"
  type        = string
}

variable "env" {
  description = "環境名（dev / prod）"
  type        = string
}

variable "hostname" {
  description = "API の公開ホスト名（例: api.example.com）"
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
