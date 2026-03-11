variable "project_id"   { type = string }
variable "region"       { type = string }
variable "environment"  { type = string }
variable "app_name"     { type = string }
variable "db_name"      { type = string }
variable "db_user"      { type = string }
variable "network"      { type = string }

variable "deletion_protection" {
  type    = bool
  default = false
}
