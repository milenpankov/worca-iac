# The images' repositories (worca-iac/registry/ecr), by name: an apply fails here, not in a pod
# stuck pulling, when they are missing.
data "aws_ecr_repository" "images" {
  for_each = var.image_repositories
  name     = each.value
}

# The Entra app registration's tenant and client id: String parameters you create (README:
# Secrets). Not secret, so read here; only the client secret goes through External Secrets.
data "aws_ssm_parameter" "entra" {
  for_each = toset(["tenant-id", "client-id"])
  name     = "${local.infra.ssm_prefix}/auth/${each.key}"
}

locals {
  ssm_prefix   = local.infra.ssm_prefix
  ecr_registry = split("/", data.aws_ecr_repository.images["controller"].repository_url)[0]

  worca_values = yamldecode(templatefile("${path.module}/values/worca-poc.yaml", {
    ecr_registry          = local.ecr_registry
    controller_repository = data.aws_ecr_repository.images["controller"].name
    worker_repository     = data.aws_ecr_repository.images["worker"].name
    image_tag             = var.worca_image_tag
    host                  = var.worca_host
    timezone              = var.timezone
    mock_mode             = var.mock_mode
    tenant_id             = data.aws_ssm_parameter.entra["tenant-id"].insecure_value
    client_id             = data.aws_ssm_parameter.entra["client-id"].insecure_value
    # The ALB IngressGroup's settings, plus the health check of oauth2-proxy (Worca's Ingress
    # backend): its /ping answers 200 without a session.
    ingress_annotations = jsonencode(merge(local.alb_annotations, {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/ping"
    }))
  }))

  # Kubernetes Secret -> { namespace, labels, data: { key = SSM sub-path under ssm_prefix } },
  # made by External Secrets.
  secrets = {
    "worca-auth" = {
      data = { "client-secret" = "auth/client-secret", "cookie-secret" = "auth/cookie-secret" }
    }
    "worca-secrets" = {
      data = { for k in var.controller_env_secrets : k => "controller/${k}" }
    }
    "worca-worker-credentials" = {
      data = { for k in var.worker_env_secrets : k => "worker/${k}" }
    }
  }
}

# Worca's namespace: the Secrets External Secrets writes must exist before Argo CD syncs the chart.
resource "kubernetes_namespace_v1" "worca" {
  metadata {
    name = "worca"
  }
}

# Storage classes, External Secrets, and the Argo CD Application. A Helm release (not
# kubernetes_manifest) so a first `apply` plans without the add-ons' CRDs present.
resource "helm_release" "bootstrap" {
  name      = "worca-bootstrap"
  namespace = "kube-system"
  chart     = "${path.module}/charts/bootstrap"

  values = [yamlencode({
    region          = local.infra.region
    efsFileSystemId = local.infra.efs_file_system_id
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

  # Destroyed first: Argo CD then deletes Worca (its Ingress leaves the ALB) while the load balancer
  # controller still runs.
  depends_on = [
    helm_release.argocd,
    helm_release.external_secrets,
    helm_release.cluster_autoscaler,
    helm_release.aws_load_balancer_controller,
  ]
}
