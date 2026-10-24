variable "account_id" {
  description = "Cloudflare アカウント ID"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare ゾーン ID"
  type        = string
}

variable "hostname" {
  description = "この環境の API ホスト名"
  type        = string
}

variable "state_bucket" {
  description = "tfstate 用 GCS バケット名（envs/<env>/gcp の出力を読む）"
  type        = string
}
