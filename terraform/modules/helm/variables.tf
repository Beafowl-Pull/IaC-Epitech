variable "app_name"       { type = string }
variable "environment"    { type = string }
variable "namespace"      { type = string }
variable "domain"         { type = string }
variable "image_repo"     { type = string }
variable "image_tag"      { type = string }
variable "cluster_issuer" { type = string }

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt ACME registration"
  type        = string
  default     = "devops@example.com"
}

variable "db_host" {
  type      = string
  sensitive = true
}

variable "db_user"     { type = string }

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_name" { type = string }

variable "jwt_secret" {
  type      = string
  sensitive = true
}

variable "api_password" {
  type      = string
  sensitive = true
}

variable "app_gcp_service_account" {
  description = "GCP service account email for Workload Identity (from GKE module)"
  type        = string
  default     = ""
}

variable "node_pool_config" {
  type = object({
    machine_type   = string
    min_node_count = number
    max_node_count = number
    disk_size_gb   = number
  })
}

variable "github_repo" {
  description = "GitHub repository in org/repo format (used for ARC runner scale set)"
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
