# Everything Worca needs in the project besides the chart: the pull secret, the service accounts
# (workers, the Vault login), what they may use (an SCC, auth-delegator; both optional), the
# Vault login's secrets and, when asked, the shared claim.

locals {
  ns = var.namespace

  pull_secrets = var.registry_username == "" ? [] : [{ name = var.pull_secret_name }]

  no_proxy = join(",", compact([var.no_proxy, "localhost,127.0.0.1,.svc,.cluster.local"]))
  proxy_env = var.http_proxy == "" ? {} : {
    HTTP_PROXY  = var.http_proxy
    HTTPS_PROXY = var.http_proxy
    NO_PROXY    = local.no_proxy
    http_proxy  = var.http_proxy
    https_proxy = var.http_proxy
    no_proxy    = local.no_proxy
  }

  kubernetes_auth = var.vault.auth_method == "kubernetes"
}

resource "kubernetes_secret_v1" "pull" {
  count = var.registry_username == "" ? 0 : 1

  metadata {
    name      = var.pull_secret_name
    namespace = local.ns
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.registry) = {
          username = var.registry_username
          password = var.registry_password
          auth     = base64encode("${var.registry_username}:${var.registry_password}")
        }
      }
    })
  }
}

resource "kubernetes_service_account_v1" "worker" {
  metadata {
    name      = var.worker_service_account
    namespace = local.ns
  }
  automount_service_account_token = false
}

# The controller's account is the chart's (`worca`, the release name); the SCC goes to both.
resource "kubernetes_role_binding_v1" "scc" {
  count = var.grant_scc == "" ? 0 : 1

  metadata {
    name      = "worca-scc-${var.grant_scc}"
    namespace = local.ns
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:openshift:scc:${var.grant_scc}"
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.release
    namespace = local.ns
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.worker.metadata[0].name
    namespace = local.ns
  }
}

# --- The Vault login ---------------------------------------------------------------------------------

resource "kubernetes_service_account_v1" "vault" {
  count = local.kubernetes_auth ? 1 : 0

  metadata {
    name      = var.vault.service_account
    namespace = local.ns
  }
}

# A long-lived token of that account: what Vault's kubernetes auth mount uses to review tokens
# (token_reviewer_jwt, README). Not needed by the operator itself.
resource "kubernetes_secret_v1" "vault_reviewer" {
  count = local.kubernetes_auth ? 1 : 0

  metadata {
    name      = "${var.vault.service_account}-token"
    namespace = local.ns
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.vault[0].metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "kubernetes_cluster_role_binding_v1" "auth_delegator" {
  count = local.kubernetes_auth && var.create_auth_delegator_binding ? 1 : 0

  metadata {
    name = "${local.ns}-${var.vault.service_account}-auth-delegator"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vault[0].metadata[0].name
    namespace = local.ns
  }
}

resource "kubernetes_secret_v1" "approle" {
  count = local.kubernetes_auth ? 0 : 1

  metadata {
    name      = "vault-approle"
    namespace = local.ns
  }
  data = {
    id = var.vault_approle_secret_id
  }
}

resource "kubernetes_secret_v1" "vault_ca" {
  count = var.vault.ca_file == "" ? 0 : 1

  metadata {
    name      = "vault-ca"
    namespace = local.ns
  }
  data = {
    "ca.crt" = file(var.vault.ca_file)
  }
}

# --- The shared claim, when this root makes it ---------------------------------------------------------

resource "kubernetes_persistent_volume_claim_v1" "shared" {
  count = var.storage.shared_existing_claim == "" && var.storage.shared_precreate ? 1 : 0

  metadata {
    name      = var.storage.shared_claim_name
    namespace = local.ns
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage.shared_class
    resources {
      requests = {
        storage = var.storage.shared_size
      }
    }
  }
  # A statically provisioned volume may only appear after the bootstrap's extra manifests.
  wait_until_bound = false
}

locals {
  shared_claim = (var.storage.shared_existing_claim != "" ? var.storage.shared_existing_claim :
  var.storage.shared_precreate ? var.storage.shared_claim_name : "")
}
