# envs/prod/terraform.tfvars
# Secrets must be passed via env vars or a secrets manager — never hardcoded here:
#   export TF_VAR_jwt_secret=$(openssl rand -hex 32)
#   export TF_VAR_api_password="yourpassword"

project_id  = "iac-epitech-489911"
region      = "europe-west1"
environment = "prod"
app_name    = "task-manager"
namespace   = "task-manager"

domain      = "tasks.aureagames.com"
image_repo  = "europe-west1-docker.pkg.dev/iac-epitech-489911/task-manager/task-manager"
image_tag   = "latest"

cluster_issuer    = "letsencrypt-prod"
letsencrypt_email = "matheo@aureagames.com"
github_repo       = "Beafowl-Pull/IaC-Epitech"

network                = "default"
subnetwork             = "default"
create_nat             = false
master_ipv4_cidr_block = "172.16.1.0/28"

node_pool_config = {
  machine_type   = "e2-standard-4"
  min_node_count = 2
  max_node_count = 10
  disk_size_gb   = 100
  disk_type      = "pd-ssd"
}

runner_pool_config = {
  machine_type   = "e2-medium"
  min_node_count = 0
  max_node_count = 5
  disk_size_gb   = 50
  disk_type      = "pd-standard"
}

db_name = "tasks"
db_user = "taskuser"
