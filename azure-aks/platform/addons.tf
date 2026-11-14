# Cluster add-ons, installed by Terraform so they exist before Argo CD deploys Worca. None of them
# tolerates the worker taints, so all run on the system node.

locals {
  ids    = local.infra.workload_identity_client_ids
  wi_use = { "azure.workload.identity/use" = "true" }

  # Every Ingress on Application Gateway for Containers: the AGC made in infra (bring your own),
  # its frontend, and a Let's Encrypt certificate from cert-manager.
  agc_annotations = {
    "alb.networking.azure.io/alb-id"       = local.infra.agc_id
    "alb.networking.azure.io/alb-frontend" = local.infra.agc_frontend
    "cert-manager.io/cluster-issuer"       = "letsencrypt"
  }
}

# Programs Application Gateway for Containers from Ingresses (class azure-alb-external) and
# Gateways. Its identity may configure that AGC and join its subnet (infra/identities.tf).
resource "helm_release" "alb_controller" {
  name             = "alb-controller"
  namespace        = "azure-alb-system"
  create_namespace = true
  repository       = "oci://mcr.microsoft.com/application-lb/charts"
  chart            = "alb-controller"
  version          = var.chart_versions.alb_controller

  values = [yamlencode({
    albController = {
      namespace   = "azure-alb-system"
      podIdentity = { clientID = local.ids["alb-controller"] }
    }
  })]
}

# Let's Encrypt certificates for both hosts, answered by DNS-01 in the Azure DNS zone.
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.chart_versions.cert_manager

  values = [yamlencode({
    crds           = { enabled = true }
    podLabels      = local.wi_use
    serviceAccount = { name = "cert-manager", labels = local.wi_use }
  })]
}

# Key Vault -> Kubernetes Secrets, read with its Workload Identity (Key Vault Secrets User).
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_versions.external_secrets

  values = [yamlencode({
    installCRDs = true
    podLabels   = local.wi_use
    serviceAccount = {
      create = true
      name   = "external-secrets"
      annotations = {
        "azure.workload.identity/client-id" = local.ids["external-secrets"]
        "azure.workload.identity/tenant-id" = local.infra.tenant_id
      }
    }
  })]
}

# Argo CD: deploys Worca from git (the Application is in the bootstrap chart), with its own login:
# the `admin` user and the password it generates at install.
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argo_cd

  values = [yamlencode({
    global        = { domain = var.argocd_host }
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs = {
      params = { "server.insecure" = true } # TLS ends at the AGC
    }
  })]
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name        = "argocd-server"
    namespace   = helm_release.argocd.namespace
    annotations = local.agc_annotations
  }

  spec {
    ingress_class_name = "azure-alb-external"
    tls {
      hosts       = [var.argocd_host]
      secret_name = "argocd-tls"
    }
    rule {
      host = var.argocd_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.alb_controller, helm_release.bootstrap]
}
