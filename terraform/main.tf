terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }

  # Remote state — change bucket name to your own
  backend "gcs" {
    bucket = "iac-epitech"
    prefix = "task-manager"
  }
}

# ── Providers ──────────────────────────────────────────────────────────────────

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Kubernetes + Helm providers are configured after GKE cluster is created
# using the cluster's endpoint and credentials.
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  load_config_file       = false
}

# ── APIs ───────────────────────────────────────────────────────────────────────

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# ── Private Services Connection (required for Cloud SQL private IP) ─────────────

resource "google_compute_global_address" "private_ip_range" {
  name          = "private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = "projects/${var.project_id}/global/networks/${var.network}"
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = "projects/${var.project_id}/global/networks/${var.network}"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [google_project_service.servicenetworking]
}

# ── Modules ────────────────────────────────────────────────────────────────────

module "gke" {
  source = "./modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "${var.app_name}-${var.environment}"
  environment  = var.environment

  node_pool_config = var.node_pool_config
  network          = var.network
  subnetwork       = var.subnetwork
}

module "cloudsql" {
  source = "./modules/cloudsql"

  project_id        = var.project_id
  region            = var.region
  environment       = var.environment
  app_name          = var.app_name
  db_name           = var.db_name
  db_user           = var.db_user
  network           = var.network
  deletion_protection = var.environment == "prod" ? true : false

  depends_on = [module.gke, google_service_networking_connection.private_vpc_connection, google_project_service.secretmanager]
}

module "helm" {
  source = "./modules/helm"

  app_name       = var.app_name
  environment    = var.environment
  namespace      = var.namespace
  domain         = var.domain
  image_repo     = var.image_repo
  image_tag      = var.image_tag
  cluster_issuer = var.cluster_issuer

  # Workload Identity — GCP SA email from GKE module
  app_gcp_service_account = module.gke.app_service_account_email

  # DB credentials from Cloud SQL module
  db_host     = module.cloudsql.private_ip
  db_user     = var.db_user
  db_password = module.cloudsql.db_password
  db_name     = var.db_name

  # Sensitive vars passed directly
  jwt_secret       = var.jwt_secret
  api_password     = var.api_password
  grafana_password = var.grafana_password

  # GitHub Actions
  github_repo = var.github_repo
  github_pat  = var.github_pat

  # Let's Encrypt
  letsencrypt_email = var.letsencrypt_email

  node_pool_config = var.node_pool_config

  depends_on = [module.gke, module.cloudsql]
}
