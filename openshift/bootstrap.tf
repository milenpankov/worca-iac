# argocd.mode = operator: an Argo CD instance of the cluster's OpenShift GitOps operator.
resource "helm_release" "argocd" {
  count = var.argocd.mode == "operator" ? 1 : 0

  name      = "worca-argocd"
  namespace = local.ns
  chart     = "${path.module}/charts/argocd"

  values = [yamlencode({
    name   = var.argocd.instance_name
    host   = var.argocd.host
    groups = var.argocd.groups
    admins = var.argocd.admins
    proxy  = local.proxy_env
    repo = {
      url     = var.worca_repo_url
      proxy   = var.http_proxy
      noProxy = var.http_proxy == "" ? "" : local.no_proxy
    }
  })]
}

locals {
  # Kubernetes Secret <- one KV v2 entry each; the entry's keys become the Secret's keys (README).
  secrets = {
    "worca-auth"               = { path = var.vault.auth_path, restart = [{ kind = "Deployment", name = "${local.release}-auth" }] }
    "worca-secrets"            = { path = var.vault.controller_path, restart = [{ kind = "StatefulSet", name = local.release }] }
    "worca-worker-credentials" = { path = var.vault.worker_path, restart = [] } # read at each worker's start
  }
}

# The Vault Secrets Operator's login and Secrets, the extra manifests and, with Argo CD, the
# Application. A Helm release (not kubernetes_manifest) so a plan works without reading CRDs.
resource "helm_release" "bootstrap" {
  name      = "worca-bootstrap"
  namespace = local.ns
  chart     = "${path.module}/charts/bootstrap"

  values = [yamlencode({
    vault = {
      address        = var.vault.address
      caSecret       = var.vault.ca_file == "" ? "" : kubernetes_secret_v1.vault_ca[0].metadata[0].name
      namespace      = var.vault.namespace
      method         = var.vault.auth_method
      mount          = var.vault.auth_mount
      role           = var.vault.role
      serviceAccount = local.kubernetes_auth ? kubernetes_service_account_v1.vault[0].metadata[0].name : ""
      roleId         = var.vault.role_id
      secretIdRef    = local.kubernetes_auth ? "" : kubernetes_secret_v1.approle[0].metadata[0].name
      kvMount        = var.vault.kv_mount
      refresh        = var.vault.refresh
    }
    secrets        = local.secrets
    extraManifests = var.extra_manifests
    application = {
      enabled        = var.argocd.mode == "operator"
      release        = local.release
      repoURL        = var.worca_repo_url
      targetRevision = var.worca_revision
      path           = "deploy/helm/worca"
      values         = local.worca_values_yaml
    }
  })]

  # Destroyed before Argo CD: Argo CD then deletes Worca while it still runs.
  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.pull,
    kubernetes_service_account_v1.worker,
    kubernetes_role_binding_v1.scc,
    kubernetes_cluster_role_binding_v1.auth_delegator,
    kubernetes_persistent_volume_claim_v1.shared,
  ]
}
