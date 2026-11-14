# --- The cluster and the project ---------------------------------------------------------------------

variable "api_url" {
  description = "The cluster's API, e.g. https://api.mycluster.example.com:6443 (`oc whoami --show-server`)."
  type        = string
}

variable "token" {
  description = "Bearer token with `admin` in the project (TF_VAR_token): a service account's (`oc create token <sa> --duration=...`) or your own (`oc whoami -t`). Never put it in a file."
  type        = string
  sensitive   = true
}

variable "ca_file" {
  description = "PEM bundle the API's certificate chains to, when it is not publicly trusted. Empty = the system trust store."
  type        = string
  default     = ""
}

variable "insecure_skip_tls_verify" {
  description = "Skip verifying the API's certificate. Only for a throwaway test cluster."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "The existing project Worca goes into (`oc new-project`, or one your platform team gave you). Argo CD runs there too."
  type        = string
}

# --- Images ------------------------------------------------------------------------------------------

variable "registry" {
  description = "Registry host the images come from, e.g. registry.example.com, or the cluster's own (image-registry.openshift-image-registry.svc:5000)."
  type        = string
}

variable "registry_username" {
  description = "Pull user for the registry (TF_VAR_registry_username). Empty = no pull secret (public registry, or the project's own image streams)."
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
  type    = string
  default = "registry-pull"
}

variable "images" {
  description = "Repositories in the registry, without the host. Argo CD's images come from the GitOps operator."
  type = object({
    worca_controller = string
    worca_worker     = string
    oauth2_proxy     = string
  })
  default = {
    worca_controller = "worca/worca"
    worca_worker     = "worca/worca-worker"
    oauth2_proxy     = "oauth2-proxy/oauth2-proxy"
  }
}

variable "worca_image_tag" {
  description = "Tag of the controller image; worker images are <tag>-<engine>."
  type        = string
  default     = "poc"
}

# --- Pod security ------------------------------------------------------------------------------------

variable "pod_security" {
  description = <<-EOT
    Who Worca's pods run as. The controller and worker image expects uid 1000.
      fs_group             null = the platform assigns it (OpenShift: from the project's range). A fixed
                           value outside that range gets the pod refused.
      supplemental_groups  extra gids, e.g. the group an NFS share grants write access to.
      oauth2_proxy_uid     null = the platform assigns it (works under restricted-v2).
    Under OpenShift's default SCC (restricted-v2) uid 1000 is refused: set grant_scc, or use a
    platform whose default SCC allows any non-root uid.
  EOT
  type = object({
    run_as_user         = optional(number, 1000)
    run_as_group        = optional(number, 1000)
    fs_group            = optional(number)
    supplemental_groups = optional(list(number), [])
    oauth2_proxy_uid    = optional(number)
  })
  default = {}
}

variable "grant_scc" {
  description = "An SCC whose use this root grants to Worca's service accounts (a RoleBinding to system:openshift:scc:<name>), e.g. \"nonroot-v2\". Needs the right to grant it (usually a cluster admin). Empty = none: the default SCC must already allow uid 1000."
  type        = string
  default     = ""
}

variable "worker_service_account" {
  description = "Service account the worker pods run as (created here). Some platforms grant per account (an SCC, a storage self-service)."
  type        = string
  default     = "worca-worker"
}

# --- Storage -----------------------------------------------------------------------------------------

variable "storage" {
  description = <<-EOT
    db: SQLite's ReadWriteOnce claim (never NFS). shared: the ReadWriteMany claim controller and
    workers share, in one of three ways:
      shared_existing_claim  a claim that already exists (made by hand or another tool);
      shared_precreate       this root makes the claim with shared_class (which may be "", for a
                             statically provisioned PV that an extra manifest or an admin creates);
      otherwise              the chart makes it with shared_class (null = the cluster default).
  EOT
  type = object({
    db_class              = optional(string)
    db_size               = optional(string, "8Gi")
    shared_class          = optional(string)
    shared_size           = optional(string, "50Gi")
    shared_existing_claim = optional(string, "")
    shared_precreate      = optional(bool, false)
    shared_claim_name     = optional(string, "worca-shared")
  })
  default = {}
}

# --- Network -----------------------------------------------------------------------------------------

variable "http_proxy" {
  description = "Outbound HTTP(S) proxy for the internet, e.g. http://proxy.example.com:8080. Empty = direct egress."
  type        = string
  default     = ""
}

variable "no_proxy" {
  description = "Hosts and CIDRs reached without the proxy (comma-separated); cluster-internal names are added."
  type        = string
  default     = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
}

variable "worca_host" {
  description = "Worca's host name, e.g. worca-myproject.apps.mycluster.example.com: under the cluster's apps domain the router's wildcard certificate and DNS already cover it."
  type        = string
}

variable "ingress_class" {
  description = "Ingress class; OpenShift turns the Ingress into a Route. openshift-default is the cluster's router; some clusters offer others (an internet-facing one, say)."
  type        = string
  default     = "openshift-default"
}

variable "ingress_annotations" {
  description = "Annotations on Worca's Ingress, copied onto its Route. The router cuts connections idle for 30 s by default: Worca's live updates need longer."
  type        = map(string)
  default = {
    "route.openshift.io/termination"      = "edge"
    "haproxy.router.openshift.io/timeout" = "1h"
  }
}

variable "tls_secret_name" {
  description = "TLS Secret for Worca's host. Empty = the router's default (wildcard) certificate."
  type        = string
  default     = ""
}

# --- Resources ---------------------------------------------------------------------------------------

variable "resources" {
  description = "Requests and limits. Shared clusters often grant far less in requests than in limits; keep the requests low. max_workers workers at their limits must fit the project's quota."
  type = object({
    controller = optional(object({ requests_cpu = string, requests_memory = string, limits_cpu = string, limits_memory = string }),
    { requests_cpu = "250m", requests_memory = "1Gi", limits_cpu = "2", limits_memory = "3Gi" })
    oauth2_proxy = optional(object({ requests_cpu = string, requests_memory = string, limits_cpu = string, limits_memory = string }),
    { requests_cpu = "25m", requests_memory = "64Mi", limits_cpu = "250m", limits_memory = "256Mi" })
    worker = optional(object({ requests_cpu = string, requests_memory = string, limits_cpu = string, limits_memory = string }),
    { requests_cpu = "250m", requests_memory = "1Gi", limits_cpu = "2", limits_memory = "4Gi" })
    max_workers = optional(number, 2)
  })
  default = {}
}

# --- Vault / OpenBao (the Vault Secrets Operator, already on the cluster) -----------------------------

variable "vault" {
  description = <<-EOT
    Where Worca's secrets live and how the Vault Secrets Operator (installed cluster-wide by the
    platform) logs in. address empty = the operator's default VaultConnection.
      auth_method  kubernetes: a service account of this project (created here) logs in; Vault's
                   kubernetes auth mount must know the cluster (README). approle: role_id here,
                   the secret ID in TF_VAR_vault_approle_secret_id.
      paths        the KV v2 entries for the three Kubernetes Secrets (README: keys).
  EOT
  type = object({
    address         = optional(string, "")
    ca_file         = optional(string, "")
    namespace       = optional(string, "")
    auth_method     = optional(string, "kubernetes")
    auth_mount      = optional(string, "kubernetes")
    role            = optional(string, "worca")
    service_account = optional(string, "worca-vault")
    role_id         = optional(string, "")
    kv_mount        = optional(string, "kv")
    refresh         = optional(string, "1h")
    auth_path       = optional(string, "worca/auth")
    controller_path = optional(string, "worca/controller")
    worker_path     = optional(string, "worca/worker")
  })
  default = {}

  validation {
    condition     = contains(["kubernetes", "approle"], var.vault.auth_method)
    error_message = "vault.auth_method is kubernetes or approle."
  }
}

variable "vault_approle_secret_id" {
  description = "AppRole secret ID (TF_VAR_vault_approle_secret_id), for vault.auth_method = approle. Lands in this root's state."
  type        = string
  default     = ""
  sensitive   = true
}

variable "create_auth_delegator_binding" {
  description = "Bind system:auth-delegator to the Vault login service account (a ClusterRoleBinding: needs cluster rights). Vault's kubernetes auth uses it to verify tokens. Where a platform offers a self-service for it instead, put that in extra_manifests."
  type        = bool
  default     = false
}

# --- Argo CD (the OpenShift GitOps operator) and Worca -------------------------------------------------

variable "argocd" {
  description = <<-EOT
    mode     operator: an ArgoCD instance of the OpenShift GitOps operator in the project, plus an
             Application that follows worca_revision. helm: no Argo CD; Terraform installs the chart
             from worca_chart_path.
    groups   OpenShift groups allowed to sign in to Argo CD (through OpenShift's login); those in
             admins get role:admin, the rest role:readonly. Empty = any user who can sign in to
             OpenShift may log in, with no rights unless in admins.
  EOT
  type = object({
    mode          = optional(string, "operator")
    instance_name = optional(string, "worca")
    host          = optional(string, "")
    groups        = optional(list(string), [])
    admins        = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["operator", "helm"], var.argocd.mode)
    error_message = "argocd.mode is operator or helm."
  }
}

variable "worca_repo_url" {
  description = "Git repository holding the Worca Helm chart (deploy/helm/worca)."
  type        = string
  default     = "https://github.com/milenpankov/worca-cc.git"
}

variable "worca_revision" {
  description = "Branch, tag or commit Argo CD deploys. A branch follows its new commits."
  type        = string
  default     = "feat/worker-containers"
}

variable "worca_chart_path" {
  description = "Local path of the chart for argocd.mode = helm (a worca-cc checkout's deploy/helm/worca)."
  type        = string
  default     = "../../worca-cc/deploy/helm/worca"
}

variable "oidc" {
  description = "Sign-in: the OpenID Connect app registration oauth2-proxy uses. Its redirect URI: https://<worca_host>/oauth2/callback. The client secret is in Vault (vault.auth_path)."
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

variable "extra_manifests" {
  description = "Further objects for the project, applied with the bootstrap (no CRD needed at plan time): whatever your platform does through its own resources, e.g. a storage or RBAC self-service. Each item is one manifest as an object (yamldecode a file, or write HCL)."
  type        = list(any)
  default     = []
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
