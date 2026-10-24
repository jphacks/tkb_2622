variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "Artifact Registry のリージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "github_repository" {
  description = "Workload Identity 連携を許可する GitHub リポジトリ（owner/name）"
  type        = string
  default     = "jphacks/tkb_2622"
}

variable "image_keep_count" {
  description = "Artifact Registry に残すイメージの最新件数．これより古く 30 日を過ぎたイメージは削除する"
  type        = number
  default     = 10
}
