# What VSO needs to log in to Vault: the AppRole's secret ID and, for a private CA, the CA bundle.
resource "kubernetes_secret_v1" "approle" {
  metadata {
    name      = "vault-approle"
    namespace = rancher2_namespace.this["worca"].name
  }
  data = {
    id = var.vault_approle_secret_id # the key VaultAuth's appRole.secretRef expects
  }
}

resource "kubernetes_secret_v1" "vault_ca" {
  count = var.vault.ca_file == "" ? 0 : 1

  metadata {
    name      = "vault-ca"
    namespace = rancher2_namespace.this["worca"].name
  }
  data = {
    "ca.crt" = file(var.vault.ca_file)
  }
}

locals {
  release = "worca" # the Worca chart's release name, so its object names below are known

  worca_values = yamldecode(templatefile("${path.module}/values/worca.yaml", {
    registry              = var.registry
    controller_repository = var.images.worca_controller
    worker_repository     = var.images.worca_worker
    oauth2_proxy          = var.images.oauth2_proxy
    image_tag             = var.worca_image_tag
    pull_secrets          = local.pull_secrets
    host                  = var.worca_host
    timezone              = var.timezone
    mock_mode             = var.mock_mode
    proxy_env             = local.proxy_env
    no_proxy              = var.http_proxy == "" ? "" : local.no_proxy
    ingress_class         = var.ingress_class
    ingress_annotations   = var.ingress_annotations
    tls_secret_name       = var.tls_secret_name
    storage               = var.storage
    worker                = var.worker
    oidc                  = var.oidc
  }))

  # Kubernetes Secret <- one KV v2 entry each; the entry's keys become the Secret's keys (README).
  secrets = {
    "worca-auth"               = { path = var.vault.auth_path, restart = [{ kind = "Deployment", name = "${local.release}-auth" }] }
    "worca-secrets"            = { path = var.vault.controller, restart = [{ kind = "StatefulSet", name = local.release }] }
    "worca-worker-credentials" = { path = var.vault.worker_path, restart = [] } # read at each worker's start
  }
}

# VSO's connection, login and the three VaultStaticSecrets, plus the Argo CD Application that
# deploys Worca. A Helm release (not kubernetes_manifest) so a first plan works before the CRDs
# exist.
resource "helm_release" "bootstrap" {
  name      = "worca-bootstrap"
  namespace = rancher2_namespace.this["worca"].name
  chart     = "${path.module}/charts/bootstrap"

  values = [yamlencode({
    vault = {
      address     = var.vault.address
      namespace   = var.vault.namespace
      caSecret    = var.vault.ca_file == "" ? "" : kubernetes_secret_v1.vault_ca[0].metadata[0].name
      approle     = var.vault.approle
      roleId      = var.vault.role_id
      secretIdRef = kubernetes_secret_v1.approle.metadata[0].name
      kvMount     = var.vault.kv_mount
      refresh     = var.vault.refresh
    }
    secrets = local.secrets
    argocd  = { namespace = helm_release.argocd.namespace }
    worca = {
      release        = local.release
      repoURL        = var.worca_repo_url
      targetRevision = var.worca_revision
      path           = "deploy/helm/worca"
      values         = local.worca_values
    }
  })]

  # Destroyed first: Argo CD then deletes Worca while it still runs.
  depends_on = [helm_release.argocd, helm_release.vault_secrets_operator]
}
