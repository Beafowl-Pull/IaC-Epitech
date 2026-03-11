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

variable "node_pool_config" {
  type = object({
    machine_type   = string
    min_node_count = number
    max_node_count = number
    disk_size_gb   = number
  })
}
