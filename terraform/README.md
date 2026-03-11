# Terraform — Task Manager Infrastructure

Déploie l'intégralité de l'infra sur GCP :
**GKE** (cluster + node pool + autoscaler) → **Cloud SQL** (PostgreSQL 16) → **Helm** (cert-manager + ingress-nginx + task-manager)

## Structure

```
terraform/
├── main.tf               # Orchestration des 3 modules
├── variables.tf          # Variables root
├── outputs.tf            # Outputs root
├── notes.tf              # Notes opérationnelles
├── .gitignore
├── modules/
│   ├── gke/              # Cluster GKE + node pool + service accounts
│   ├── cloudsql/         # Instance PostgreSQL + Secret Manager
│   └── helm/             # cert-manager + ingress-nginx + task-manager chart
└── envs/
    ├── staging/terraform.tfvars
    └── prod/terraform.tfvars
```

## Prérequis

```bash
# Outils
terraform >= 1.6
gcloud CLI (authentifié)
helm >= 3.12
kubectl

# Activer les APIs GCP
gcloud services enable \
  container.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  servicenetworking.googleapis.com \
  --project YOUR_PROJECT_ID

# Créer le bucket GCS pour le remote state
gsutil mb -p YOUR_PROJECT_ID gs://YOUR_PROJECT_ID-tfstate
gsutil versioning set on gs://YOUR_PROJECT_ID-tfstate
```

## Déploiement

### 1. Configurer les variables

Éditer `envs/staging/terraform.tfvars` ou `envs/prod/terraform.tfvars` :
- Remplacer `YOUR_PROJECT_ID` par ton vrai project ID
- Changer `domain` par ton vrai domaine
- Changer `image_repo` par ton registry

### 2. Passer les secrets par variables d'environnement (ne jamais les mettre dans les tfvars)

```bash
export TF_VAR_jwt_secret=$(openssl rand -hex 32)
export TF_VAR_api_password="un-mot-de-passe-fort"
```

### 3. Init + Plan + Apply

```bash
cd terraform

terraform init

# Staging
terraform plan -var-file=envs/staging/terraform.tfvars
terraform apply -var-file=envs/staging/terraform.tfvars

# Prod
terraform plan -var-file=envs/prod/terraform.tfvars
terraform apply -var-file=envs/prod/terraform.tfvars
```

### 4. Configurer kubectl

```bash
# La commande exacte est dans les outputs terraform
terraform output kubeconfig_command
# ex: gcloud container clusters get-credentials task-manager-prod --region europe-west1 --project YOUR_PROJECT
```

### 5. Vérifier le déploiement

```bash
# Pods
kubectl get pods -n task-manager

# HPA
kubectl get hpa -n task-manager

# Certificat TLS (peut prendre 2-3 min pour Let's Encrypt)
kubectl get certificate -n task-manager

# URL publique
terraform output app_url
```

## Rotation des secrets

```bash
# Rotation du mot de passe DB
terraform taint module.cloudsql.random_password.db_password
terraform apply -var-file=envs/prod/terraform.tfvars
# → Cloud SQL reçoit le nouveau mot de passe, Helm déclenche un rolling restart automatique
```

## Destruction

```bash
# Staging uniquement (deletion_protection=false)
terraform destroy -var-file=envs/staging/terraform.tfvars

# Prod : deletion_protection=true sur Cloud SQL → à désactiver manuellement d'abord
```
