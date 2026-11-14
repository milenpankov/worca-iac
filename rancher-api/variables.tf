# --- Rancher and the cluster -------------------------------------------------------------------

variable "rancher_url" {
  description = "Rancher server URL, e.g. https://rancher.example.com (a trailing /v3 is fine)."
  type        = string
}

variable "rancher_token" {
  description = "Rancher API token (token-xxxxx:secret) of an account that is cluster owner on the cluster. Export TF_VAR_rancher_token; never put it in a file."
  type        = string
  sensitive   = true
}

variable "rancher_ca_file" {
  description = "PEM bundle the Rancher server's certificate chains to, when it is a private CA. Empty = the system trust store."
  type        = string
  default     = ""
}

variable "cluster_id" {
  description = "Rancher cluster ID (c-xxxxx or c-m-xxxxxxxx): Cluster Management, or the URL of the cluster's page."
  type        = string
}

# --- Rancher project and namespaces ------------------------------------------------------------

variable "existing_project_id" {
  description = "Put the namespaces in this existing Rancher project (c-xxxxx:p-yyyyy) instead of creating one. Its quotas then apply as they are."
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Name of the Rancher project this root creates (unless existing_project_id)."
  type        = string
  default     = "worca"
}

variable "namespace_prefix" {
  description = "Prepended to the three namespace names (argocd, vault-secrets-operator, worca), e.g. \"team-\"."
  type        = string
  default     = ""
}

variable "project_quota" {
  description = "The created project's resource quota: the ceiling for all its namespaces together. Must be at least the sum of namespace_quotas."
  type = object({
    limits_cpu      = string
    limits_memory   = string
    requests_cpu    = string
    requests_memory = string
    pods            = optional(string)
  })
  default = {
    limits_cpu      = "16000m"
    limits_memory   = "32Gi"
    requests_cpu    = "6000m"
    requests_memory = "16Gi"
    pods            = "60"
  }
}

variable "namespace_quotas" {
  description = "Each namespace's own quota (Rancher's field.cattle.io/resourceQuota). worca must hold the controller, oauth2-proxy and worker.max_workers workers at their limits. {} = none, for an existing project without a quota (Rancher refuses namespace quotas there)."
  type = map(object({
    limits_cpu      = string
    limits_memory   = string
    requests_cpu    = string
    requests_memory = string
    pods            = optional(string)
  }))
  default = {
    argocd = {
      limits_cpu      = "4000m"
      limits_memory   = "6Gi"
      requests_cpu    = "1000m"
      requests_memory = "2Gi"
    }
    vault-secrets-operator = {
      limits_cpu      = "1000m"
      limits_memory   = "512Mi"
      requests_cpu    = "100m"
      requests_memory = "256Mi"
    }
    worca = {
      limits_cpu      = "10000m"
      limits_memory   = "20Gi"
      requests_cpu    = "4000m"
      requests_memory = "8Gi"
    }
  }

  validation {
    condition     = length(var.namespace_quotas) == 0 || alltrue([for k in ["argocd", "vault-secrets-operator", "worca"] : contains(keys(var.namespace_quotas), k)])
    error_message = "namespace_quotas needs the keys argocd, vault-secrets-operator and worca, or none at all (an existing project without quotas)."
  }
}

variable "container_default_resources" {
  description = "Rancher's container default limits (a LimitRange in every namespace of the created project): what a container gets when its chart sets no requests or limits. A quota on limits.cpu rejects such pods otherwise."
  type = object({
    limits_cpu      = string
    limits_memory   = string
    requests_cpu    = string
    requests_memory = string
  })
  default = {
    limits_cpu      = "500m"
    limits_memory   = "512Mi"
    requests_cpu    = "50m"
    requests_memory = "64Mi"
  }
}

# --- Images: an internal registry ----------------------------------------------------------------

variable "registry" {
  description = "Registry host the cluster pulls from, e.g. registry.example.com. The pull secret is for this host."
  type        = string
}

variable "registry_username" {
  description = "Pull user for the registry (TF_VAR_registry_username). Empty = no pull secret (anonymous pulls)."
  type        = string
  default     = ""
}

variable "registry_password" {
  description = "Pull token for the registry (TF_VAR_registry_password)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "pull_secret_name" {
  description = "Name of the docker-registry Secret created in each namespace."
  type        = string
  default     = "registry-pull"
}

variable "images" {
  description = "Image repositories in the registry, without the host (README: what to mirror). Tags are the charts' own, except Worca's (worca_image_tag)."
  type = object({
    worca_controller = string
    worca_worker     = string
    oauth2_proxy     = string
    argocd           = string
    redis            = string
    vso              = string
    kube_rbac_proxy  = string
  })
  default = {
    worca_controller = "worca/worca"
    worca_worker     = "worca/worca-worker"
    oauth2_proxy     = "oauth2-proxy/oauth2-proxy"
    argocd           = "argoproj/argocd"
    redis            = "docker/library/redis"
    vso              = "hashicorp/vault-secrets-operator"
    kube_rbac_proxy  = "brancz/kube-rbac-proxy"
  }
}

variable "worca_image_tag" {
  description = "Tag of the controller image; worker images are <tag>-<engine>."
  type        = string
  default     = "poc"
}

# --- Network ---------------------------------------------------------------------------------------

variable "http_proxy" {
  description = "Outbound HTTP(S) proxy, e.g. http://proxy.example.com:8080. Empty = direct egress. Set for the controller (and so the workers), oauth2-proxy and Argo CD's git access."
  type        = string
  default     = ""
}

variable "no_proxy" {
  description = "Hosts and CIDRs reached without the proxy (comma-separated): add the Vault server and internal git hosts. Cluster-internal names are added on top."
  type        = string
  default     = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
}

variable "ingress_class" {
  description = "Ingress class of the cluster's ingress controller."
  type        = string
  default     = "nginx"
}

variable "ingress_annotations" {
  description = "Extra annotations on both Ingresses (Worca and Argo CD), e.g. a cert-manager issuer."
  type        = map(string)
  default     = {}
}

variable "tls_secret_name" {
  description = "TLS Secret of both Ingresses, in their namespaces. Empty = the ingress controller's default certificate (a wildcard for the cluster's domain, typically)."
  type        = string
  default     = ""
}

variable "worca_host" {
  description = "Host name of Worca, e.g. worca.apps.example.com. DNS must already resolve it to the ingress controller (typically a wildcard)."
  type        = string
}

variable "argocd_host" {
  description = "Host name of the Argo CD UI, e.g. argocd-worca.apps.example.com."
  type        = string
}

# --- Storage ---------------------------------------------------------------------------------------

variable "storage" {
  description = "Storage classes: db is ReadWriteOnce (SQLite; never NFS), shared must be ReadWriteMany (NFS, CephFS, Longhorn RWX, ...). Empty class = the cluster default. prepare chowns the shared volume's directories once, for NFS exports where fsGroup does not apply."
  type = object({
    db_class     = optional(string, "")
    db_size      = optional(string, "8Gi")
    shared_class = string
    shared_size  = optional(string, "50Gi")
    prepare      = optional(bool, true)
  })
}

# --- Vault / OpenBao (Vault Secrets Operator) ------------------------------------------------------

variable "install_vault_secrets_operator" {
  description = "Install the Vault Secrets Operator. Set false when the cluster already runs one (two would both reconcile every VaultStaticSecret)."
  type        = bool
  default     = true
}

variable "vault" {
  description = "Where Worca's secrets live: a Vault or OpenBao server, its KV v2 mount and the AppRole VSO logs in with. paths: the KV entries for the three Kubernetes Secrets (README: keys)."
  type = object({
    address     = string
    namespace   = optional(string, "")
    ca_file     = optional(string, "")
    approle     = optional(string, "approle")
    role_id     = string
    kv_mount    = optional(string, "kv")
    refresh     = optional(string, "1h")
    auth_path   = optional(string, "worca/auth")
    controller  = optional(string, "worca/controller")
    worker_path = optional(string, "worca/worker")
  })
}

variable "vault_approle_secret_id" {
  description = "Secret ID of the AppRole (TF_VAR_vault_approle_secret_id). Stored as a Kubernetes Secret for VSO, and so in this root's state."
  type        = string
  sensitive   = true
}

# --- Argo CD and Worca -----------------------------------------------------------------------------

variable "argocd_install_crds" {
  description = "Install Argo CD's CRDs. Set false when another Argo CD on the cluster already installed them (Helm refuses CRDs another release owns)."
  type        = bool
  default     = true
}

variable "worca_repo_url" {
  description = "Git repository holding the Worca Helm chart (deploy/helm/worca). Public, so Argo CD needs no credentials."
  type        = string
  default     = "https://github.com/milenpankov/worca-cc.git"
}

variable "worca_revision" {
  description = "Branch, tag or commit Argo CD deploys. A branch follows its new commits."
  type        = string
  default     = "feat/worker-containers"
}

variable "oidc" {
  description = "Sign-in: the OpenID Connect app registration oauth2-proxy uses. Its redirect URI: https://<worca_host>/oauth2/callback. The client secret is in Vault (auth_path)."
  type = object({
    issuer_url   = string
    jwks_url     = optional(string, "")
    client_id    = string
    scope        = optional(string, "openid email profile offline_access")
    email_claim  = optional(string, "email")
    teams_claim  = optional(string, "groups")
    allow_groups = optional(list(string), [])
  })
}

variable "worker" {
  description = "Worker pods: how many at once, their resources, and where they may run."
  type = object({
    max_workers     = optional(number, 2)
    requests_cpu    = optional(string, "500m")
    requests_memory = optional(string, "1536Mi")
    limits_cpu      = optional(string, "2000m")
    limits_memory   = optional(string, "4Gi")
    node_selector   = optional(map(string), {})
    tolerations     = optional(list(any), [])
  })
  default = {}
}

variable "mock_mode" {
  description = "WORCA_MOCK=1: canned agent replies, no model tokens."
  type        = bool
  default     = false
}

variable "timezone" {
  type    = string
  default = "Europe/Berlin"
}

variable "chart_versions" {
  type = object({
    argo_cd                = string
    vault_secrets_operator = string
  })
  default = {
    argo_cd                = "10.18.0"
    vault_secrets_operator = "1.6.2"
  }
}

variable "chart_repositories" {
  description = "Helm repositories of the add-ons; point them at an internal mirror when the cluster's network cannot reach the public ones."
  type = object({
    argo_cd                = string
    vault_secrets_operator = string
  })
  default = {
    argo_cd                = "https://argoproj.github.io/argo-helm"
    vault_secrets_operator = "https://helm.releases.hashicorp.com"
  }
}
