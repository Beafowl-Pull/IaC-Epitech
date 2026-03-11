# ── Namespace ──────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
    labels = {
      environment                            = var.environment
      "app.kubernetes.io/managed-by"         = "terraform"
    }
  }
}

# ── cert-manager ───────────────────────────────────────────────────────────────

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.14.4"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }

  # Wait for all pods to be ready before proceeding
  wait    = true
  timeout = 300
}

# ── ClusterIssuers (Let's Encrypt staging + prod) ─────────────────────────────

resource "kubernetes_manifest" "cluster_issuer_staging" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-staging-account-key"
        }
        solvers = [{
          http01 = {
            ingress = {
              ingressClassName = "nginx"
            }
          }
        }]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_manifest" "cluster_issuer_prod" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [{
          http01 = {
            ingress = {
              ingressClassName = "nginx"
            }
          }
        }]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

# ── ingress-nginx ──────────────────────────────────────────────────────────────

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.0"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.replicaCount"
    value = var.environment == "prod" ? "2" : "1"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  # Forward real client IP from GCP LB
  set {
    name  = "controller.config.use-forwarded-headers"
    value = "true"
  }

  set {
    name  = "controller.config.compute-full-forwarded-for"
    value = "true"
  }

  wait    = true
  timeout = 300
}

# ── task-manager Helm release ─────────────────────────────────────────────────

resource "helm_release" "task_manager" {
  name      = var.app_name
  chart     = "${path.module}/../../../helm"
  namespace = kubernetes_namespace.app.metadata[0].name

  # Rolling upgrades, not full re-creates
  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  # ── Image ──────────────────────────────────────────────────────────────────
  set {
    name  = "image.repository"
    value = var.image_repo
  }
  set {
    name  = "image.tag"
    value = var.image_tag
  }

  # ── Ingress / TLS ──────────────────────────────────────────────────────────
  set {
    name  = "ingress.enabled"
    value = "true"
  }
  set {
    name  = "ingress.hosts[0].host"
    value = var.domain
  }
  set {
    name  = "ingress.hosts[0].paths[0].path"
    value = "/"
  }
  set {
    name  = "ingress.hosts[0].paths[0].pathType"
    value = "Prefix"
  }
  set {
    name  = "tls.clusterIssuer"
    value = var.cluster_issuer
  }

  # ── Secrets (sensitive — never stored in state as plaintext) ───────────────
  set_sensitive {
    name  = "secrets.jwtSecret"
    value = var.jwt_secret
  }
  set_sensitive {
    name  = "secrets.dbPassword"
    value = var.db_password
  }
  set_sensitive {
    name  = "secrets.apiPassword"
    value = var.api_password
  }

  # ── Database ───────────────────────────────────────────────────────────────
  set {
    name  = "secrets.dbHost"
    value = var.db_host
  }
  set {
    name  = "secrets.dbUser"
    value = var.db_user
  }
  set {
    name  = "secrets.dbName"
    value = var.db_name
  }

  # ── Scaling ────────────────────────────────────────────────────────────────
  set {
    name  = "autoscaling.enabled"
    value = "true"
  }
  set {
    name  = "autoscaling.minReplicas"
    value = var.environment == "prod" ? "2" : "1"
  }
  set {
    name  = "autoscaling.maxReplicas"
    value = var.environment == "prod" ? "10" : "3"
  }

  # ── Service account annotation for Workload Identity ──────────────────────
  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = var.app_gcp_service_account
  }

  depends_on = [
    helm_release.cert_manager,
    helm_release.ingress_nginx,
    kubernetes_manifest.cluster_issuer_prod,
    kubernetes_manifest.cluster_issuer_staging,
  ]
}

# ── kube-prometheus-stack (Prometheus + Grafana) ───────────────────────────────

resource "helm_release" "kube_prometheus_stack" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "58.2.2"
  namespace        = "monitoring"
  create_namespace = true

  set {
    name  = "grafana.ingress.enabled"
    value = "true"
  }
  set {
    name  = "grafana.ingress.ingressClassName"
    value = "nginx"
  }
  set {
    name  = "grafana.ingress.hosts[0]"
    value = "grafana.${var.domain}"
  }
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_password
  }
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"
  }
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  wait    = true
  timeout = 600

  depends_on = [helm_release.ingress_nginx]
}

# ── GitHub Actions Runner Controller (ARC) ─────────────────────────────────────

resource "helm_release" "arc_controller" {
  name             = "arc"
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set-controller"
  version          = "0.9.3"
  namespace        = "arc-systems"
  create_namespace = true
  wait             = true
  timeout          = 300
}

resource "helm_release" "arc_runner_set" {
  name             = "arc-runner-set"
  repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart            = "gha-runner-scale-set"
  version          = "0.9.3"
  namespace        = "arc-runners"
  create_namespace = true

  set {
    name  = "githubConfigUrl"
    value = "https://github.com/${var.github_repo}"
  }
  set_sensitive {
    name  = "githubConfigSecret.github_token"
    value = var.github_pat
  }
  set {
    name  = "minRunners"
    value = "0"
  }
  set {
    name  = "maxRunners"
    value = var.environment == "prod" ? "5" : "2"
  }
  set {
    name  = "template.spec.nodeSelector.environment"
    value = var.environment
  }

  depends_on = [helm_release.arc_controller]
}
