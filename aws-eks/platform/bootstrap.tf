locals {
  ssm_prefix = local.infra.ssm_prefix

  worca_values = yamldecode(templatefile("${path.module}/values/worca-poc.yaml", {
    ecr_registry          = local.infra.ecr_registry
    controller_repository = trimprefix(local.infra.ecr_repositories["worca"], "${local.infra.ecr_registry}/")
    worker_repository     = trimprefix(local.infra.ecr_repositories["worca-worker"], "${local.infra.ecr_registry}/")
    image_tag             = var.worca_image_tag
    host                  = var.worca_host
    tenant_id             = var.entra_tenant_id
    client_id             = var.entra_client_id
    allowed_roles         = jsonencode(var.allowed_roles)
    timezone              = var.timezone
    mock_mode             = var.mock_mode
  }))

  # Kubernetes Secret -> SSM parameters (<ssm_prefix>/<path>/<key>), made by External Secrets.
  secrets = {
    "worca-auth"               = { path = "auth", keys = ["client-secret", "cookie-secret"] }
    "worca-secrets"            = { path = "controller", keys = var.controller_env_secrets }
    "worca-worker-credentials" = { path = "worker", keys = var.worker_env_secrets }
  }
}

# Worca's namespace: the Secrets External Secrets writes must exist before Argo CD syncs the chart.
resource "kubernetes_namespace_v1" "worca" {
  metadata {
    name = "worca"
  }
}

# Storage classes, Let's Encrypt issuers, External Secrets, and the Argo CD Application. A Helm
# release (not kubernetes_manifest) so a first `apply` plans without the add-ons' CRDs present.
resource "helm_release" "bootstrap" {
  name      = "worca-bootstrap"
  namespace = "kube-system"
  chart     = "${path.module}/charts/bootstrap"

  values = [yamlencode({
    region          = local.infra.region
    efsFileSystemId = local.infra.efs_file_system_id
    acmeEmail       = var.acme_email
    ssmPrefix       = local.ssm_prefix
    namespace       = kubernetes_namespace_v1.worca.metadata[0].name
    secrets         = local.secrets
    argocd          = { namespace = helm_release.argocd.namespace }
    worca = {
      repoURL        = var.worca_repo_url
      targetRevision = var.worca_revision
      path           = "deploy/helm/worca"
      values         = local.worca_values
    }
  })]

  depends_on = [
    helm_release.argocd,
    helm_release.cert_manager,
    helm_release.external_secrets,
    helm_release.traefik,
    helm_release.cluster_autoscaler,
  ]
}
