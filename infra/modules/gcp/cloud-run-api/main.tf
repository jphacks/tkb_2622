locals {
  name_prefix = "tkb-${var.env}"

  labels = {
    env        = var.env
    managed-by = "terraform"
  }

  # Secret の値は Terraform で扱わない．作成後に gcloud secrets versions add で投入する．
  secrets = {
    database_url           = "${local.name_prefix}-database-url"
    migration_database_url = "${local.name_prefix}-migration-database-url"
  }
}

# ---------- サービスアカウント ----------

resource "google_service_account" "api" {
  account_id   = "${local.name_prefix}-api"
  display_name = "tkb ${var.env} API runtime"
}

resource "google_service_account" "migrate" {
  account_id   = "${local.name_prefix}-migrate"
  display_name = "tkb ${var.env} DB migration job"
}

resource "google_service_account_iam_member" "deployer_act_as" {
  for_each = var.deployer_service_account_email == null ? {} : {
    api     = google_service_account.api.name
    migrate = google_service_account.migrate.name
  }

  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deployer_service_account_email}"
}

# ---------- Secret Manager ----------

resource "google_secret_manager_secret" "this" {
  for_each = local.secrets

  secret_id = each.value
  labels    = local.labels

  replication {
    auto {}
  }
}

# API は実行用接続だけ，Job はマイグレーション用接続だけを読める
resource "google_secret_manager_secret_iam_member" "api_database_url" {
  secret_id = google_secret_manager_secret.this["database_url"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.api.member
}

resource "google_secret_manager_secret_iam_member" "migrate_database_url" {
  secret_id = google_secret_manager_secret.this["migration_database_url"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.migrate.member
}

# ---------- 迂回防止用の共有シークレット ----------
# Cloudflare Worker が X-Origin-Auth ヘッダーで付与し，API はこれがないリクエストを拒否する．
# 値は ephemeral で生成して書き込み専用属性で投入するため，この state には残らない．
# origin_auth_token_version を上げると新しい値を生成する（入れ替え）．

ephemeral "random_password" "origin_auth_token" {
  length  = 48
  special = false
}

resource "google_secret_manager_secret" "origin_auth_token" {
  secret_id = "${local.name_prefix}-origin-auth-token"
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "origin_auth_token" {
  secret                 = google_secret_manager_secret.origin_auth_token.id
  secret_data_wo         = ephemeral.random_password.origin_auth_token.result
  secret_data_wo_version = var.origin_auth_token_version
}

resource "google_secret_manager_secret_iam_member" "api_origin_auth_token" {
  secret_id = google_secret_manager_secret.origin_auth_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.api.member
}

# ---------- Cloud Run: API ----------

resource "google_cloud_run_v2_service" "api" {
  name     = "${local.name_prefix}-api"
  location = var.region
  labels   = local.labels

  # Cloudflare Workers から run.app URL へ転送するため公開する．認証は API が JWT で行い，
  # Worker を経由しない直接アクセスは ORIGIN_AUTH_TOKEN の検証で拒否する．
  ingress              = "INGRESS_TRAFFIC_ALL"
  invoker_iam_disabled = true
  deletion_protection  = var.deletion_protection

  template {
    service_account = google_service_account.api.email
    labels          = local.labels

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.initial_image

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle = true
      }

      env {
        name  = "SUPABASE_JWT_ISSUER"
        value = var.supabase_jwt_issuer
      }
      env {
        name  = "SUPABASE_JWT_AUDIENCE"
        value = var.supabase_jwt_audience
      }
      env {
        name  = "DB_MAX_CONNECTIONS"
        value = tostring(var.db_max_connections)
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.this["database_url"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "ORIGIN_AUTH_TOKEN"
        value_source {
          secret_key_ref {
            secret = google_secret_manager_secret.origin_auth_token.secret_id
            # 版を固定し，入れ替え時に新しいリビジョンを作らせる
            version = google_secret_manager_secret_version.origin_auth_token.version
          }
        }
      }
    }
  }

  lifecycle {
    # イメージは CI（gcloud run deploy）が更新する
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_secret_manager_secret_iam_member.api_database_url,
    google_secret_manager_secret_iam_member.api_origin_auth_token,
  ]
}

# ---------- Cloud Run: マイグレーション Job ----------

resource "google_cloud_run_v2_job" "migrate" {
  name                = "${local.name_prefix}-migrate"
  location            = var.region
  labels              = local.labels
  deletion_protection = var.deletion_protection

  template {
    labels = local.labels

    # 同時に複数のマイグレーションを走らせない
    parallelism = 1
    task_count  = 1

    template {
      service_account = google_service_account.migrate.email
      max_retries     = 0
      timeout         = "300s"

      containers {
        image   = var.initial_image
        command = ["/app/migrate"]
        args    = ["up"]

        env {
          name = "MIGRATION_DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.this["migration_database_url"].secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [google_secret_manager_secret_iam_member.migrate_database_url]
}
