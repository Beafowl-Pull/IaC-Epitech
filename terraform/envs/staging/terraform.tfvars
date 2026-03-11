# envs/staging/terraform.tfvars
# Secrets must be passed via env vars or a secrets manager — never hardcoded here:
#   export TF_VAR_jwt_secret=$(openssl rand -hex 32)
#   export TF_VAR_api_password="yourpassword"

project_id  = "YOUR_PROJECT_ID"
region      = "europe-west1"
environment = "staging"
app_name    = "task-manager"
namespace   = "task-manager"

domain      = "tasks-staging.example.com"
image_repo  = "gcr.io/YOUR_PROJECT_ID/task-manager"
image_tag   = "latest"

cluster_issuer    = "letsencrypt-staging"
letsencrypt_email = "devops@example.com"
github_repo       = "ORG/REPO"

network    = "default"
subnetwork = "default"

node_pool_config = {
  machine_type   = "e2-standard-2"
  min_node_count = 1
  max_node_count = 3
  disk_size_gb   = 50
}

db_name = "tasks"
db_user = "taskuser"
