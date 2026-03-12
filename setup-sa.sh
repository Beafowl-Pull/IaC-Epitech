#!/usr/bin/env bash
# setup-sa.sh — Bootstrap the GitHub Actions service account and WIF pool.
# Run this once as a project owner before triggering the CI pipeline.
#
# Usage: ./setup-sa.sh

set -euo pipefail

PROJECT_ID="iac-epitech-489911"
PROJECT_NUMBER="115779801723"
SA_NAME="github-actions-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
WIF_POOL="github-actions-pool-v3"
WIF_PROVIDER="github-actions-provider"
GITHUB_REPO="Beafowl-Pull/IaC-Epitech"

echo "==> Setting project to ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

# ── Service Account ───────────────────────────────────────────────────────────

echo "==> Creating service account ${SA_NAME} (skipped if exists)"
gcloud iam service-accounts create "${SA_NAME}" \
  --display-name="GitHub Actions Service Account" \
  --description="Used by GitHub Actions via Workload Identity Federation" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "    SA already exists, skipping."

# ── IAM roles ─────────────────────────────────────────────────────────────────

echo "==> Granting IAM roles to ${SA_EMAIL}"

ROLES=(
  "roles/container.admin"
  "roles/container.developer"
  "roles/artifactregistry.writer"
  "roles/storage.admin"
  "roles/iam.serviceAccountUser"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.workloadIdentityPoolAdmin"
  "roles/compute.viewer"
  "roles/compute.networkAdmin"
  "roles/servicenetworking.networksAdmin"
  "roles/resourcemanager.projectIamAdmin"
  "roles/secretmanager.admin"
  "roles/cloudsql.admin"
)

for ROLE in "${ROLES[@]}"; do
  echo "    ${ROLE}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --quiet
done

# ── Workload Identity Pool ────────────────────────────────────────────────────

echo "==> Creating WIF pool ${WIF_POOL} (skipped if exists)"
gcloud iam workload-identity-pools create "${WIF_POOL}" \
  --location=global \
  --display-name="GitHub Actions Pool" \
  --description="Identity pool for GitHub Actions OIDC" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "    Pool already exists, skipping."

echo "==> Creating WIF provider ${WIF_PROVIDER} (skipped if exists)"
gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER}" \
  --location=global \
  --workload-identity-pool="${WIF_POOL}" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == '${GITHUB_REPO}'" \
  --project="${PROJECT_ID}" 2>/dev/null || {
    echo "    Provider already exists, updating attribute condition."
    gcloud iam workload-identity-pools providers update-oidc "${WIF_PROVIDER}" \
      --location=global \
      --workload-identity-pool="${WIF_POOL}" \
      --attribute-condition="assertion.repository == '${GITHUB_REPO}'" \
      --project="${PROJECT_ID}"
  }

# ── Bind WIF pool to SA ───────────────────────────────────────────────────────

echo "==> Binding WIF pool to ${SA_EMAIL}"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/attribute.repository/${GITHUB_REPO}" \
  --project="${PROJECT_ID}"

# ── Output for GitHub secrets ─────────────────────────────────────────────────

echo ""
echo "==> Done. Set these as GitHub Actions secrets:"
echo ""
echo "    WIF_PROVIDER    = projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"
echo "    WIF_SERVICE_ACCOUNT = ${SA_EMAIL}"
