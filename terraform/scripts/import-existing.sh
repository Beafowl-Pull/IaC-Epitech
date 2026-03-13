#!/usr/bin/env bash
# import-existing.sh — Import GCP resources that already exist into Terraform state.
# Idempotent: skips resources already in state.
#
# Usage: ./import-existing.sh <env> <tf_var_args...>
# Example: ./import-existing.sh staging -var-file=envs/staging/terraform.tfvars -var="jwt_secret=..."

set -euo pipefail

ENV="${1}"
shift
TF_VARS=("$@")

PROJECT_ID="iac-epitech-489911"
PROJECT_NUMBER="115779801723"
APP_NAME="task-manager"
REGION="europe-west1"

WIF_POOL="github-actions-pool-v3"
WIF_PROVIDER="github-actions-provider"
SA_EMAIL="github-actions-sa@${PROJECT_ID}.iam.gserviceaccount.com"

CLUSTER_NAME="${APP_NAME}-${ENV}"
NODES_SA="${CLUSTER_NAME}-nodes@${PROJECT_ID}.iam.gserviceaccount.com"
APP_SA="${CLUSTER_NAME}-app@${PROJECT_ID}.iam.gserviceaccount.com"
DB_INSTANCE="${CLUSTER_NAME}-db"
DB_SECRET="${APP_NAME}-${ENV}-db-password"
DB_NAME="tasks"
DB_USER="taskuser"
ROUTER_NAME="${APP_NAME}-${ENV}-router"
NAT_NAME="${APP_NAME}-${ENV}-nat"

import_if_missing() {
  local resource="$1"
  local id="$2"
  if terraform state show "${resource}" > /dev/null 2>&1; then
    echo "  [skip] ${resource} already in state"
  else
    echo "  [import] ${resource}"
    terraform import "${TF_VARS[@]}" "${resource}" "${id}" || echo "  [warn] import failed for ${resource}, may not exist yet"
  fi
}

echo "==> Importing existing resources for env=${ENV}"

# ── Global / project-level resources ──────────────────────────────────────────
import_if_missing \
  google_iam_workload_identity_pool.github \
  "projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${WIF_POOL}"

import_if_missing \
  google_iam_workload_identity_pool_provider.github \
  "projects/${PROJECT_ID}/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"

import_if_missing \
  google_service_account.github_actions \
  "projects/${PROJECT_ID}/serviceAccounts/${SA_EMAIL}"

import_if_missing \
  google_compute_global_address.private_ip_range \
  "projects/${PROJECT_ID}/global/addresses/private-ip-range"

import_if_missing \
  google_service_networking_connection.private_vpc_connection \
  "projects/${PROJECT_ID}/global/networks/default:servicenetworking.googleapis.com"

import_if_missing \
  google_compute_router.nat_router \
  "projects/${PROJECT_ID}/regions/${REGION}/routers/${ROUTER_NAME}"

import_if_missing \
  google_compute_router_nat.nat \
  "${PROJECT_ID}/${REGION}/${ROUTER_NAME}/${NAT_NAME}"

import_if_missing \
  google_project_service.secretmanager \
  "${PROJECT_ID}/secretmanager.googleapis.com"

import_if_missing \
  google_project_service.servicenetworking \
  "${PROJECT_ID}/servicenetworking.googleapis.com"

# ── GKE ───────────────────────────────────────────────────────────────────────
import_if_missing \
  module.gke.google_service_account.gke_nodes \
  "projects/${PROJECT_ID}/serviceAccounts/${NODES_SA}"

import_if_missing \
  module.gke.google_service_account.app \
  "projects/${PROJECT_ID}/serviceAccounts/${APP_SA}"

import_if_missing \
  module.gke.google_container_cluster.main \
  "projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_NAME}"

# ── Cloud SQL ─────────────────────────────────────────────────────────────────
import_if_missing \
  module.cloudsql.google_sql_database_instance.main \
  "${DB_INSTANCE}"

import_if_missing \
  module.cloudsql.google_secret_manager_secret.db_password \
  "projects/${PROJECT_NUMBER}/secrets/${DB_SECRET}"

import_if_missing \
  module.cloudsql.google_sql_database.main \
  "${DB_INSTANCE}/${DB_NAME}"

import_if_missing \
  module.cloudsql.google_sql_user.main \
  "${DB_INSTANCE}/${DB_USER}"

echo "==> Import step complete"
