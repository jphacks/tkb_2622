# 認証は環境変数 CLOUDFLARE_API_TOKEN から読む
provider "cloudflare" {}

# 迂回防止用シークレットを Secret Manager から読むため．認証は ADC（gcloud auth application-default login）
provider "google" {}
