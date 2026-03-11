# Pass the GKE app service account to the Helm module so
# the Kubernetes ServiceAccount gets the Workload Identity annotation.
# This file extends main.tf — kept separate for clarity.

# Override the helm module's app_gcp_service_account with the value
# produced by the GKE module.
# (Already wired in main.tf via the module block — this file documents it.)

# To verify Workload Identity after deploy:
#   kubectl describe sa task-manager -n task-manager
#   # Should show annotation: iam.gke.io/gcp-service-account: ...

# To rotate the DB password (zero-downtime):
#   terraform taint module.cloudsql.random_password.db_password
#   terraform apply
#   # Helm will pick up the new password via set_sensitive and trigger a rollout
