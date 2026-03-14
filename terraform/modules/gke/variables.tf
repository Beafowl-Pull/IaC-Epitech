variable "project_id"   { type = string }
variable "region"       { type = string }
variable "cluster_name" { type = string }
variable "environment"  { type = string }
variable "network"      { type = string }
variable "subnetwork"   { type = string }
variable "namespace" {
  type    = string
  default = "task-manager"
}

variable "master_ipv4_cidr_block" {
  type    = string
  default = "172.16.0.0/28"
}

variable "node_pool_config" {
  type = object({
    machine_type   = string
    min_node_count = number
    max_node_count = number
    disk_size_gb   = number
    disk_type      = optional(string, "pd-standard")
  })
}

variable "runner_pool_config" {
  description = "GKE node pool configuration for ARC runners"
  type = object({
    machine_type   = string
    min_node_count = number
    max_node_count = number
    disk_size_gb   = number
    disk_type      = optional(string, "pd-standard")
  })
  default = {
    machine_type   = "e2-medium"
    min_node_count = 0
    max_node_count = 3
    disk_size_gb   = 50
    disk_type      = "pd-standard"
  }
}
