resource "google_container_cluster" "main" {
  provider = google-beta

  name     = var.cluster_name
  location = var.region

  # We manage node pools separately — remove the default one
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    disk_type    = "pd-standard"
    disk_size_gb = 30
  }

  # Networking
  network    = var.network
  subnetwork = var.subnetwork

  # Workload Identity — allows pods to assume GCP service accounts
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private cluster — nodes have no public IPs
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all (restrict in prod)"
    }
  }

  # Security
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  release_channel {
    channel = var.environment == "prod" ? "STABLE" : "REGULAR"
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  # Logging & monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=DAILY"
    }
  }

  deletion_protection = var.environment == "prod" ? true : false

  lifecycle {
    ignore_changes = [initial_node_count, node_config, private_cluster_config]
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# ── Node Pool ──────────────────────────────────────────────────────────────────

resource "google_container_node_pool" "main" {
  name     = "${var.cluster_name}-node-pool"
  cluster  = google_container_cluster.main.name
  location = var.region

  # Node autoscaling drives horizontal scaling
  autoscaling {
    min_node_count = var.node_pool_config.min_node_count
    max_node_count = var.node_pool_config.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.node_pool_config.machine_type
    disk_size_gb = var.node_pool_config.disk_size_gb
    disk_type    = var.node_pool_config.disk_type

    # Workload Identity on each node
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Minimal OAuth scopes — workload identity handles the rest
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    service_account = google_service_account.gke_nodes.email

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      environment = var.environment
      app         = "task-manager"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Runner Node Pool (dedicated for ARC runners) ──────────────────────────────

resource "google_container_node_pool" "runners" {
  name     = "${var.cluster_name}-runner-pool"
  cluster  = google_container_cluster.main.name
  location = var.region

  autoscaling {
    min_node_count = var.runner_pool_config.min_node_count
    max_node_count = var.runner_pool_config.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.runner_pool_config.machine_type
    disk_size_gb = var.runner_pool_config.disk_size_gb
    disk_type    = var.runner_pool_config.disk_type

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    service_account = google_service_account.gke_nodes.email

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      environment = var.environment
      node-pool   = "runner"
    }

    taint {
      key    = "dedicated"
      value  = "runner"
      effect = "NO_SCHEDULE"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Service Account for GKE nodes ─────────────────────────────────────────────

resource "google_service_account" "gke_nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE Node Pool SA — ${var.cluster_name}"
}

resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ── Service Account for the app (Workload Identity) ───────────────────────────

resource "google_service_account" "app" {
  account_id   = "${var.cluster_name}-app"
  display_name = "Task Manager App SA — ${var.cluster_name}"
}

resource "google_project_iam_member" "app_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Bind Kubernetes SA to GCP SA via Workload Identity
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.cluster_name}]"

  depends_on = [google_container_cluster.main]
}
