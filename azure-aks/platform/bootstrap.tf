# The Entra app registration's tenant and client id: Key Vault secrets you set (README). Not secret,
# so read here; the client secret only goes through External Secrets.
data "azurerm_key_vault" "this" {
  name                = local.infra.key_vault_name
  resource_group_name = local.infra.key_vault_resource_group
}

data "azurerm_key_vault_secret" "entra" {
  for_each     = toset(["auth-tenant-id", "auth-client-id"])
  name         = each.key
  key_vault_id = data.azurerm_key_vault.this.id
}

locals {
  kv_name = { for n in distinct(concat(var.controller_env_secrets, var.worker_env_secrets)) : n => replace(n, "_", "-") }

  worca_values = yamldecode(templatefile("${path.module}/values/worca-poc.yaml", {
    registry              = local.infra.acr_login_server
    controller_repository = var.image_repositories.controller
    worker_repository     = var.image_repositories.worker
    image_tag             = var.worca_image_tag
    host                  = var.worca_host
    timezone              = var.timezone
    mock_mode             = var.mock_mode
    tenant_id             = data.azurerm_key_vault_secret.entra["auth-tenant-id"].value
    client_id             = data.azurerm_key_vault_secret.entra["auth-client-id"].value
    ingress_annotations   = jsonencode(local.agc_annotations)
  }))

  # Kubernetes Secret -> { data: { key = Key Vault secret name } }, made by External Secrets.
  secrets = {
    "worca-auth" = {
      data = { "client-secret" = "auth-client-secret", "cookie-secret" = "auth-cookie-secret" }
    }
    "worca-secrets" = {
      data = { for k in var.controller_env_secrets : k => "controller-${local.kv_name[k]}" }
    }
    "worca-worker-credentials" = {
      data = { for k in var.worker_env_secrets : k => "worker-${local.kv_name[k]}" }
    }
  }
}

resource "kubernetes_namespace_v1" "worca" {
  metadata {
    name = "worca"
  }
}

# Storage class, the Let's Encrypt issuer, the Key Vault store and its ExternalSecrets, the AGC
# health checks, and the Argo CD Application. A Helm release (not kubernetes_manifest) so a first
# apply plans without the add-ons' CRDs present.
resource "helm_release" "bootstrap" {
  name      = "worca-bootstrap"
  namespace = "kube-system"
  chart     = "${path.module}/charts/bootstrap"

  values = [yamlencode({
    namespace = kubernetes_namespace_v1.worca.metadata[0].name
    keyVault  = { url = local.infra.key_vault_uri }
    secrets   = local.secrets
    letsencrypt = {
      email   = var.letsencrypt_email
      staging = var.letsencrypt_staging
      azureDNS = {
        subscriptionID    = local.infra.subscription_id
        resourceGroupName = local.infra.dns_resource_group
        hostedZoneName    = local.infra.dns_zone
        clientID          = local.ids["cert-manager"]
      }
    }
    argocd = { namespace = helm_release.argocd.namespace }
    worca = {
      repoURL        = var.worca_repo_url
      targetRevision = var.worca_revision
      path           = "deploy/helm/worca"
      values         = local.worca_values
    }
  })]

  # Destroyed first: Argo CD then deletes Worca (its Ingress leaves the AGC) while the ALB
  # controller still runs.
  depends_on = [
    helm_release.argocd,
    helm_release.external_secrets,
    helm_release.cert_manager,
    helm_release.alb_controller,
  ]
}
