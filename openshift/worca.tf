# The Worca chart's values (deploy/helm/worca in worca-cc), built here rather than templated: a
# null removes one of the chart's defaults (fsGroup, say), and yamlencode keeps it.
#
#   controller   executor kubernetes: a worker pod per run and chat thread, in this project
#   storage      SQLite on a ReadWriteOnce claim; everything shared on a ReadWriteMany claim
#   ingress      an Ingress that OpenShift turns into an edge-terminated Route
#   sign-in      oauth2-proxy + your OpenID Connect provider
#   secrets      Kubernetes Secrets synced by the Vault Secrets Operator from Vault / OpenBao

locals {
  release = "worca" # the chart's release name: its service account and object names follow it

  pod_security = merge(
    {
      runAsNonRoot   = true
      runAsUser      = var.pod_security.run_as_user
      runAsGroup     = var.pod_security.run_as_group
      seccompProfile = { type = "RuntimeDefault" }
    },
    var.pod_security.fs_group == null ? { fsGroup = null, fsGroupChangePolicy = null } : { fsGroup = var.pod_security.fs_group },
    length(var.pod_security.supplemental_groups) == 0 ? {} : { supplementalGroups = var.pod_security.supplemental_groups },
  )

  res = { for k, r in { controller = var.resources.controller, auth = var.resources.oauth2_proxy, worker = var.resources.worker } : k => {
    requests = { cpu = r.requests_cpu, memory = r.requests_memory }
    limits   = { cpu = r.limits_cpu, memory = r.limits_memory }
  } }

  worca_values = {
    image = {
      registry   = var.registry
      repository = var.images.worca_controller
      tag        = var.worca_image_tag
      pullPolicy = "Always" # the PoC re-pushes the same tag
    }
    imagePullSecrets = local.pull_secrets

    controller = {
      executor           = "kubernetes"
      env                = merge({ TZ = var.timezone }, var.mock_mode ? { WORCA_MOCK = "1" } : {}, { for k, v in local.proxy_env : k => v if lower(k) != "no_proxy" })
      extraNoProxy       = var.http_proxy == "" ? "" : local.no_proxy
      resources          = local.res.controller
      podSecurityContext = local.pod_security
    }

    # CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN, ...: Secret worca-secrets (VSO, from Vault).
    secrets = { existingSecret = "worca-secrets" }

    worker = {
      image              = { registry = var.registry, repository = var.images.worca_worker }
      credentialsSecret  = "worca-worker-credentials"
      serviceAccountName = var.worker_service_account
      podSecurityContext = local.pod_security
      maxWorkers         = var.resources.max_workers
      idleTimeoutSeconds = 600
      resources          = local.res.worker
    }

    storage = {
      db = merge({ size = var.storage.db_size }, var.storage.db_class == null ? {} : { storageClassName = var.storage.db_class })
      shared = merge(
        { size = var.storage.shared_size, prepare = { enabled = false } }, # a root init container: refused by OpenShift's SCCs
        local.shared_claim != "" ? { existingClaim = local.shared_claim } : {},
        local.shared_claim == "" && var.storage.shared_class != null ? { storageClassName = var.storage.shared_class } : {},
      )
    }

    ingress = {
      enabled     = true
      className   = var.ingress_class
      annotations = var.ingress_annotations
      hosts       = [{ host = var.worca_host, paths = [{ path = "/", pathType = "Prefix" }] }]
      tls         = [merge({ hosts = [var.worca_host] }, var.tls_secret_name == "" ? {} : { secretName = var.tls_secret_name })]
    }

    # The app registration's redirect URI: https://<worca_host>/oauth2/callback.
    auth = {
      enabled = true
      image   = { registry = var.registry, repository = var.images.oauth2_proxy }
      oidc = merge(
        {
          issuerUrl  = var.oidc.issuer_url
          clientId   = var.oidc.client_id
          scope      = var.oidc.scope
          emailClaim = var.oidc.email_claim
          teamsClaim = var.oidc.teams_claim
        },
        var.oidc.jwks_url == "" ? {} : { jwksUrl = var.oidc.jwks_url },
      )
      allowedGroups  = var.oidc.allow_groups
      existingSecret = "worca-auth" # client-secret, cookie-secret (VSO, from Vault)
      env            = local.proxy_env
      resources      = local.res.auth
      podSecurityContext = {
        runAsNonRoot   = true
        runAsUser      = var.pod_security.oauth2_proxy_uid
        runAsGroup     = var.pod_security.oauth2_proxy_uid
        seccompProfile = { type = "RuntimeDefault" }
      }
    }
  }

  worca_values_yaml = yamlencode(local.worca_values)
}

# argocd.mode = helm: no Argo CD, the chart straight from a local checkout.
resource "helm_release" "worca" {
  count = var.argocd.mode == "helm" ? 1 : 0

  name      = local.release
  namespace = local.ns
  chart     = var.worca_chart_path
  values    = [local.worca_values_yaml]
  wait      = false # the controller waits for its Secrets, which VSO makes from the bootstrap

  depends_on = [helm_release.bootstrap]
}
