resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ── Cloud SQL PostgreSQL Instance ──────────────────────────────────────────────

resource "google_sql_database_instance" "main" {
  name             = "${var.app_name}-${var.environment}-db"
  database_version = "POSTGRES_16"
  region           = var.region

  deletion_protection = var.deletion_protection

  lifecycle {
    ignore_changes = [
      settings[0].disk_size, # autoresize changes this
    ]
  }

  settings {
    tier              = var.environment == "prod" ? "db-custom-2-7680" : "db-f1-micro"
    availability_type = var.environment == "prod" ? "REGIONAL" : "ZONAL"
    disk_autoresize   = true
    disk_size         = 20
    disk_type         = "PD_SSD"

    # Private IP only — no public endpoint
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.main.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = var.environment == "prod" ? true : false
      backup_retention_settings {
        retained_backups = var.environment == "prod" ? 14 : 3
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000" # log queries slower than 1s
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }
  }
}

# ── Database & User ────────────────────────────────────────────────────────────

resource "google_sql_database" "main" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "main" {
  name     = var.db_user
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}

# ── Store password in Secret Manager ──────────────────────────────────────────

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.app_name}-${var.environment}-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# ── Network data source ────────────────────────────────────────────────────────

data "google_compute_network" "main" {
  name = var.network
}
