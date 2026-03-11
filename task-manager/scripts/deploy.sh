#!/bin/bash
# Usage: ./scripts/deploy.sh [staging|prod]
set -euo pipefail

ENV="${1:-staging}"
NAMESPACE="task-manager"
RELEASE="task-manager"
CHART="./helm/task-manager"
IMAGE_REPO="${IMAGE_REPO:-gcr.io/YOUR_PROJECT/task-manager}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

: "${JWT_SECRET:?JWT_SECRET is required}"
: "${DB_HOST:?DB_HOST is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${API_PASSWORD:?API_PASSWORD is required}"
: "${DOMAIN:?DOMAIN is required (e.g. tasks.example.com)}"

if [[ "$ENV" == "prod" ]]; then
  CLUSTER_ISSUER="letsencrypt-prod"
  warn "Deploying to PRODUCTION on domain: $DOMAIN"
else
  CLUSTER_ISSUER="letsencrypt-staging"
  info "Deploying to STAGING on domain: $DOMAIN"
fi

info "Creating namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

info "Building Docker image $IMAGE_REPO:$IMAGE_TAG..."
docker build -t "$IMAGE_REPO:$IMAGE_TAG" -t "$IMAGE_REPO:latest" .
info "Pushing image..."
docker push "$IMAGE_REPO:$IMAGE_TAG"
docker push "$IMAGE_REPO:latest"

info "Deploying Helm chart (release: $RELEASE, env: $ENV)..."
helm upgrade --install "$RELEASE" "$CHART" -f ../helm/values.yaml \
  --namespace "$NAMESPACE" \
  --wait \
  --timeout 5m

info "Waiting for deployment rollout..."
kubectl rollout status deployment/"$RELEASE" -n "$NAMESPACE" --timeout=3m

info "Checking pod status..."
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=task-manager"

info "Checking HPA..."
kubectl get hpa -n "$NAMESPACE"

echo ""
info "✅ Deployment complete!"
info "   URL: https://$DOMAIN"
info "   Get token: curl -k -X POST https://$DOMAIN/auth/token -H 'Content-Type: application/json' -d '{\"username\":\"admin\",\"password\":\"YOUR_PASSWORD\"}'"
