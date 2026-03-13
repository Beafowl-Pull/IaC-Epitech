# ── Project ────────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Deployment environment (staging or prod)"
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be 'staging' or 'prod'."
  }
}

# ── App ────────────────────────────────────────────────────────────────────────

variable "app_name" {
  description = "Application name, used as prefix for all resources"
  type        = string
  default     = "task-manager"
}

variable "namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "task-manager"
}

variable "domain" {
  description = "Public domain for the application (e.g. tasks.example.com)"
  type        = string
}

variable "image_repo" {
  description = "Docker image repository (e.g. gcr.io/PROJECT/task-manager)"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name"
  type        = string
  default     = "letsencrypt-prod"
}

# ── Network ────────────────────────────────────────────────────────────────────

variable "create_nat" {
  description = "Whether to create a Cloud NAT router. Set to false if one already exists for the network (e.g. prod shares staging's NAT)."
  type        = bool
  default     = true
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "VPC subnetwork name"
  type        = string
  default     = "default"
}

# ── GKE Node Pool ──────────────────────────────────────────────────────────────

variable "node_pool_config" {
  description = "GKE node pool configuration"
  type = object({
    machine_type   = string
    min_node_count = number
    max_node_count = number
    disk_size_gb   = number
    disk_type      = optional(string, "pd-standard")
  })
  default = {
    machine_type   = "e2-standard-2"
    min_node_count = 1
    max_node_count = 5
    disk_size_gb   = 50
    disk_type      = "pd-standard"
  }
}

# ── Database ───────────────────────────────────────────────────────────────────

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "tasks"
}

variable "db_user" {
  description = "PostgreSQL user name"
  type        = string
  default     = "taskuser"
}

# ── Secrets (use -var-file or env TF_VAR_*) ───────────────────────────────────

variable "jwt_secret" {
  description = "JWT signing secret — must be at least 32 characters"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.jwt_secret) >= 32
    error_message = "jwt_secret must be at least 32 characters."
  }
}

variable "api_password" {
  description = "Password for the API admin user"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.api_password) >= 12
    error_message = "api_password must be at least 12 characters."
  }
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt ACME registration"
  type        = string
  default     = "devops@example.com"
}

variable "github_repo" {
  description = "GitHub repository in org/repo format (e.g. my-org/task-manager)"
  type        = string
  default     = "ORG/REPO"
}

variable "github_pat" {
  description = "GitHub PAT with repo scope for ARC runner registration"
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}
