# envs/prod/terraform.tfvars
# Secrets must be passed via env vars or a secrets manager — never hardcoded here:
#   export TF_VAR_jwt_secret=$(openssl rand -hex 32)
#   export TF_VAR_api_password="yourpassword"

project_id  = "YOUR_PROJECT_ID"
region      = "europe-west1"
environment = "prod"
app_name    = "task-manager"
namespace   = "task-manager"

domain      = "tasks.example.com"
image_repo  = "gcr.io/YOUR_PROJECT_ID/task-manager"
image_tag   = "1.0.0"   # pin to a specific tag in prod, never use "latest"

cluster_issuer    = "letsencrypt-prod"
letsencrypt_email = "devops@example.com"
github_repo       = "ORG/REPO"

network    = "default"
subnetwork = "default"

node_pool_config = {
  machine_type   = "e2-standard-4"
  min_node_count = 2
  max_node_count = 10
  disk_size_gb   = 100
}

db_name = "tasks"
db_user = "taskuser"
