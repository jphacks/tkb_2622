variable "account_id" {
  description = "Cloudflare アカウント ID"
  type        = string
}

variable "workers_dev_subdomain" {
  description = "アカウントの workers.dev サブドメイン名．hostname を指定しない場合に workers.dev で公開する"
  type        = string
  default     = null
}

variable "hostname" {
  description = "カスタムドメインで公開する場合の API ホスト名．null なら workers.dev で公開する"
  type        = string
  default     = null
}

variable "zone_id" {
  description = "hostname を置く Cloudflare ゾーン ID．hostname を指定する場合に必須"
  type        = string
  default     = null
}

variable "state_bucket" {
  description = "tfstate 用 GCS バケット名（envs/<env>/gcp の出力を読む）"
  type        = string
}
