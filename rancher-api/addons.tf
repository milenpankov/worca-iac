# The two add-ons Worca needs here, installed by Terraform so they exist before Argo CD deploys it:
# the Vault Secrets Operator (Worca's secrets) and Argo CD (Worca itself, from git). Both pull from
# the internal registry with the pull secret. Every container gets explicit resources, so the
# namespace quotas hold.

resource "helm_release" "vault_secrets_operator" {
  count = var.install_vault_secrets_operator ? 1 : 0

  name       = "vault-secrets-operator"
  namespace  = rancher2_namespace.this["vault-secrets-operator"].name
  repository = var.chart_repositories.vault_secrets_operator
  chart      = "vault-secrets-operator"
  version    = var.chart_versions.vault_secrets_operator

  values = [yamlencode({
    controller = {
      imagePullSecrets = local.pull_secrets
      manager          = { image = { repository = local.image.vso } }
      kubeRbacProxy    = { image = { repository = local.image.kube_rbac_proxy } }
    }
  })]

  depends_on = [kubernetes_secret_v1.pull]
}

# Argo CD under its own release name: its ClusterRoles (worca-argocd-*) and the resources it
# tracks (installationID) cannot clash with another Argo CD on the same cluster.
resource "helm_release" "argocd" {
  name       = "worca-argocd"
  namespace  = rancher2_namespace.this["argocd"].name
  repository = var.chart_repositories.argo_cd
  chart      = "argo-cd"
  version    = var.chart_versions.argo_cd
  timeout    = 600

  values = [yamlencode({
    crds = { install = var.argocd_install_crds, keep = true }
    global = {
      domain           = var.argocd_host
      image            = { repository = local.image.argocd }
      imagePullSecrets = local.pull_secrets
    }
    dex            = { enabled = false }
    notifications  = { enabled = false }
    applicationSet = { enabled = false }

    configs = {
      params = { "server.insecure" = true } # TLS ends at the ingress controller
      cm     = { installationID = "worca" }
      repositories = {
        worca = merge(
          { url = var.worca_repo_url, type = "git", name = "worca" },
          var.http_proxy == "" ? {} : { proxy = var.http_proxy, noProxy = local.no_proxy },
        )
      }
    }

    controller = { resources = { requests = { cpu = "250m", memory = "512Mi" }, limits = { cpu = "1000m", memory = "2Gi" } } }
    repoServer = { resources = { requests = { cpu = "100m", memory = "256Mi" }, limits = { cpu = "1000m", memory = "1Gi" } } }
    server     = { resources = { requests = { cpu = "50m", memory = "128Mi" }, limits = { cpu = "500m", memory = "512Mi" } } }
    redis = {
      image     = { repository = local.image.redis }
      resources = { requests = { cpu = "50m", memory = "64Mi" }, limits = { cpu = "500m", memory = "256Mi" } }
    }
  })]

  depends_on = [kubernetes_secret_v1.pull]
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name        = "argocd-server"
    namespace   = helm_release.argocd.namespace
    annotations = var.ingress_annotations
  }

  spec {
    ingress_class_name = var.ingress_class
    tls {
      hosts       = [var.argocd_host]
      secret_name = var.tls_secret_name == "" ? null : var.tls_secret_name
    }
    rule {
      host = var.argocd_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "worca-argocd-server"
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
  }
}
