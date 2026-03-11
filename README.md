# Task Manager API

A production-ready REST API for task management, written in **Go**, deployed on **GKE** via **Terraform** + **Helm**, with a full **GitHub Actions** CI/CD pipeline.

## Stack

| Component | Choice |
|-----------|--------|
| Language | Go 1.22 |
| Router | gorilla/mux |
| Database | PostgreSQL (Cloud SQL) |
| Auth | JWT (HS256) |
| TLS | cert-manager + Let's Encrypt |
| Container | Docker multi-stage (scratch) |
| Orchestration | GKE (Google Kubernetes Engine) |
| Infrastructure | Terraform |
| CI/CD | GitHub Actions |
| GCP Auth | Workload Identity Federation (no long-lived keys) |
| Self-hosted runners | Actions Runner Controller (ARC) on GKE |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana) |

---

## API Reference

All endpoints require:
```
Authorization: Bearer <token>
correlation_id: <trace-id>
```

### Authentication

```http
POST /auth/token
Content-Type: application/json

{ "username": "admin", "password": "yourpassword" }
```

Returns `{ "token": "...", "expires_at": "..." }` — use the token as a Bearer.

### Tasks

| Method | Path | Description | Body |
|--------|------|-------------|------|
| POST | /tasks | Create task | `{title, content, due_date, request_timestamp}` |
| GET | /tasks | List all tasks | — |
| GET | /tasks/{id} | Get task | — |
| PUT | /tasks/{id} | Update task | `{title?, content?, due_date?, done?, request_timestamp}` |
| DELETE | /tasks/{id} | Delete task | `{request_timestamp}` |

### HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | Success (GET/PUT/DELETE) |
| 201 | Created (POST) |
| 400 | Bad Request — invalid body |
| 401 | Unauthorized — missing/invalid token |
| 404 | Not Found |
| 409 | Conflict — stale `request_timestamp` |
| 429 | Too Many Requests — rate limit hit |
| 500 | Internal Server Error |

---

## Out-of-Order Request Handling

Every mutating request includes a `request_timestamp`. The database stores `last_timestamp` per task:

- **PUT/DELETE**: Only applied if `request_timestamp > last_timestamp`. Otherwise → **409 Conflict**.
- This guarantees that a delayed older request can never overwrite a newer one.

---

## Local Development

### 1. Generate TLS cert
```bash
chmod +x scripts/gen-certs.sh
./scripts/gen-certs.sh localhost
```

### 2. Start with Docker Compose
```bash
docker-compose up --build
```

### 3. Get a token
```bash
curl -k -X POST https://localhost:8443/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"adminpassword"}'
```

### 4. Create a task
```bash
TOKEN="<token-from-above>"
curl -k -X POST https://localhost:8443/tasks \
  -H "Authorization: Bearer $TOKEN" \
  -H "correlation_id: abc123" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Write tests",
    "content": "Unit + integration tests for the API",
    "due_date": "2025-09-30",
    "request_timestamp": "2025-09-25T20:00:00Z"
  }'
```

---

## Infrastructure (Terraform)

All cloud resources are managed by Terraform under `terraform/`. Two environments are supported: `staging` and `prod`.

### What Terraform provisions

| Resource | Details |
|----------|---------|
| GKE cluster | Autopilot-compatible node pool with cluster autoscaler |
| Cloud SQL | PostgreSQL 15, private IP, deletion protection on prod |
| cert-manager | Let's Encrypt ClusterIssuers (staging + prod) |
| ingress-nginx | GCP LoadBalancer, real IP forwarding |
| Helm release | task-manager app with HPA |
| ARC controller | GitHub Actions self-hosted runner controller |
| ARC runner set | Ephemeral runner pods (0–5 on prod, 0–2 on staging) |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana) |
| WIF pool | Workload Identity Federation for GitHub Actions |

### Bootstrap (one-time, run locally)

```bash
cd terraform

# Export secrets — never hardcode these
export TF_VAR_jwt_secret=$(openssl rand -hex 32)
export TF_VAR_api_password="your-api-password"
export TF_VAR_grafana_password="your-grafana-password"
export TF_VAR_github_pat="ghp_..."   # GitHub PAT with repo scope

# Staging
terraform init -backend-config="prefix=task-manager/staging"
terraform apply -var-file="envs/staging/terraform.tfvars"

# Prod
terraform init -backend-config="prefix=task-manager/prod"
terraform apply -var-file="envs/prod/terraform.tfvars"
```

After apply, retrieve the WIF outputs for GitHub Actions secrets:

```bash
terraform output workload_identity_provider
terraform output github_actions_service_account
```

### Customise before deploying

Edit the placeholder values in the tfvars files:

| File | Values to update |
|------|-----------------|
| `terraform/envs/staging/terraform.tfvars` | `project_id`, `domain`, `image_repo`, `letsencrypt_email`, `github_repo` |
| `terraform/envs/prod/terraform.tfvars` | same as above + `image_tag` |
| `terraform/main.tf` | GCS backend bucket name |

---

## CI/CD (GitHub Actions)

Three workflows live in `.github/workflows/`:

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `ci.yml` | Pull Request → `main` / `develop` | `terraform fmt` check, `validate`, `plan` for both envs — posts plans as PR comments |
| `deploy.yml` | Push to `main` / manual dispatch | Build + push Docker image → apply staging → apply prod (requires manual approval) |
| `destroy.yml` | Manual dispatch only | `terraform destroy` for the chosen environment |

All workflows authenticate to GCP via **Workload Identity Federation** — no service account key files.

Runners use `${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}`:
- Before bootstrap: falls back to GitHub-hosted `ubuntu-latest`
- After bootstrap: set `RUNNER_LABEL=arc-runner-set` to use ARC pods in GKE

### GitHub Actions setup

#### 1. Secrets (Settings → Secrets and variables → Actions → Secrets)

| Secret | Value |
|--------|-------|
| `WIF_PROVIDER` | `terraform output workload_identity_provider` |
| `WIF_SERVICE_ACCOUNT` | `terraform output github_actions_service_account` |
| `JWT_SECRET` | `openssl rand -hex 32` |
| `API_PASSWORD` | API admin password (≥ 12 chars) |
| `GRAFANA_PASSWORD` | Grafana admin password |
| `GIT_PAT` | GitHub PAT with `repo` scope (for ARC) |

#### 2. Variables (Settings → Secrets and variables → Actions → Variables)

| Variable | Value |
|----------|-------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `RUNNER_LABEL` | Set to `arc-runner-set` after bootstrap |

#### 3. GitHub Environments (Settings → Environments)

Create these four environments:

| Environment | Protection rules |
|-------------|-----------------|
| `staging` | None (auto-deploy) |
| `prod` | Required reviewers |
| `staging-plan` | None |
| `prod-plan` | None |

---

## Workload Identity Federation

GitHub Actions authenticates to GCP without any service account key files, using short-lived OIDC tokens.

```
GitHub Actions job
  → presents OIDC token (JWT signed by GitHub)
    → GCP WIF pool verifies token against https://token.actions.githubusercontent.com
      → exchanges for short-lived GCP access token scoped to github-actions-sa
        → workflow can push images, run terraform, deploy to GKE
```

The WIF resources are defined in `terraform/github-oidc.tf` and are created automatically by `terraform apply`.

---

## Monitoring

Prometheus and Grafana are deployed via `kube-prometheus-stack` in the `monitoring` namespace.

Access Grafana:
```bash
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Open http://localhost:3000 — login: admin / <GRAFANA_PASSWORD>
```

Grafana is also exposed via ingress at `https://grafana.<your-domain>`.

---

## HPA + Node Scaling

The Helm chart deploys an HPA that scales pods from **2 to 10 replicas** (prod) or **1 to 3** (staging) based on CPU (70%) and memory (80%) usage.

The GKE cluster autoscaler handles node-level scaling automatically.

Pods use `podAntiAffinity` to spread across nodes.

---

## Security

- No long-lived GCP credentials — Workload Identity Federation only
- No secrets in `values.yaml` or `*.tfvars` — all injected via `TF_VAR_*` env vars or `set_sensitive`
- `*.tfvars`, `*.tfstate`, `.terraform/`, `kubeconfig`, `*.pem` are all gitignored
- HTTPS only (TLS 1.2+, strong cipher suites)
- JWT authentication on all `/tasks` routes
- Secrets stored in Kubernetes Secrets (not plain env vars)
- Non-root container (`nobody`, UID 65534)
- Read-only root filesystem
- All Linux capabilities dropped
- Pod disruption budget for HA
- Rate limiting per IP (50 req/s)
- Request correlation via `correlation_id` header
- Graceful shutdown (30s drain)
- DB connection pool + retry on startup
- Parameterized SQL queries (no injection)

---

## Project Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml          # PR: fmt + validate + plan (staging & prod)
│       ├── deploy.yml      # Push to main: build image → staging → prod
│       └── destroy.yml     # Manual: terraform destroy
├── helm/
│   ├── Chart.yaml
│   ├── values.yaml         # No secrets — injected by Terraform
│   └── templates/
│       ├── _helpers.tpl
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── secret.yaml
│       ├── serviceaccount.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml
│       ├── pdb.yaml
│       └── networkpolicy.yaml
├── terraform/
│   ├── main.tf             # Providers, module wiring
│   ├── variables.tf        # All input variables
│   ├── github-oidc.tf      # Workload Identity Federation resources
│   ├── modules/
│   │   ├── gke/            # GKE cluster + node pool + Workload Identity SA
│   │   ├── cloudsql/       # Cloud SQL PostgreSQL instance
│   │   └── helm/
│   │       ├── main.tf     # cert-manager, nginx, app, ARC, monitoring
│   │       └── variables.tf
│   └── envs/
│       ├── staging/
│       │   └── terraform.tfvars
│       └── prod/
│           └── terraform.tfvars
└── task-manager/           # Go application source
    ├── main.go
    ├── Dockerfile
    ├── docker-compose.yml
    ├── go.mod
    ├── scripts/
    │   └── gen-certs.sh
    └── internal/
        ├── handlers/       # tasks.go, auth.go, context.go
        ├── middleware/     # auth, logger, rate limiter, request ID
        ├── models/         # task.go, errors.go
        └── db/             # connection + migration
```
