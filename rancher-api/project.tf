# A Rancher project with a quota and container defaults, and Worca's three namespaces in it.
# Rancher namespaces (not plain Kubernetes ones): Rancher sets the project annotation and each
# namespace's quota itself, and checks the quotas fit the project's.

resource "rancher2_project" "this" {
  count = var.existing_project_id == "" ? 1 : 0

  cluster_id  = var.cluster_id
  name        = var.project_name
  description = "Worca: Argo CD, the Vault Secrets Operator and Worca (worca-iac/rancher-api)"

  resource_quota {
    project_limit {
      limits_cpu      = var.project_quota.limits_cpu
      limits_memory   = var.project_quota.limits_memory
      requests_cpu    = var.project_quota.requests_cpu
      requests_memory = var.project_quota.requests_memory
      pods            = var.project_quota.pods
    }
    # What a namespace gets without a quota of its own. Every namespace here has one
    # (namespace_quotas), so this only matters for namespaces added by hand.
    namespace_default_limit {
      limits_cpu      = "1000m"
      limits_memory   = "1Gi"
      requests_cpu    = "250m"
      requests_memory = "512Mi"
    }
  }

  container_resource_limit {
    limits_cpu      = var.container_default_resources.limits_cpu
    limits_memory   = var.container_default_resources.limits_memory
    requests_cpu    = var.container_default_resources.requests_cpu
    requests_memory = var.container_default_resources.requests_memory
  }
}

locals {
  project_id = var.existing_project_id != "" ? var.existing_project_id : rancher2_project.this[0].id

  namespaces = {
    argocd                 = "${var.namespace_prefix}argocd"
    vault-secrets-operator = "${var.namespace_prefix}vault-secrets-operator"
    worca                  = "${var.namespace_prefix}worca"
  }
}

resource "rancher2_namespace" "this" {
  for_each = local.namespaces

  name       = each.value
  project_id = local.project_id

  dynamic "resource_quota" {
    for_each = length(var.namespace_quotas) > 0 ? [var.namespace_quotas[each.key]] : []
    content {
      limit {
        limits_cpu      = resource_quota.value.limits_cpu
        limits_memory   = resource_quota.value.limits_memory
        requests_cpu    = resource_quota.value.requests_cpu
        requests_memory = resource_quota.value.requests_memory
        pods            = resource_quota.value.pods
      }
    }
  }
}

# Image pull secret in each namespace, for the one registry every image comes from.
resource "kubernetes_secret_v1" "pull" {
  for_each = var.registry_username == "" ? {} : local.namespaces

  metadata {
    name      = var.pull_secret_name
    namespace = rancher2_namespace.this[each.key].name
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

locals {
  pull_secrets = var.registry_username == "" ? [] : [{ name = var.pull_secret_name }]
  image        = { for k, repo in var.images : k => "${var.registry}/${repo}" }

  no_proxy = join(",", compact([var.no_proxy, "localhost,127.0.0.1,.svc,.cluster.local"]))
  proxy_env = var.http_proxy == "" ? {} : {
    HTTP_PROXY  = var.http_proxy
    HTTPS_PROXY = var.http_proxy
    NO_PROXY    = local.no_proxy
    http_proxy  = var.http_proxy
    https_proxy = var.http_proxy
    no_proxy    = local.no_proxy
  }
}
