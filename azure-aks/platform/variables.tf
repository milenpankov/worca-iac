variable "infra_state_path" {
  description = "The infra root's state file."
  type        = string
  default     = "../infra/terraform.tfstate"
}

# --- Worca (installed by Argo CD from git) ---------------------------------------------------

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

variable "image_repositories" {
  description = "Repositories of the controller and worker images in the registry (worca-iac/registry/acr)."
  type = object({
    controller = string
    worker     = string
  })
  default = {
    controller = "worca-poc/worca"
    worker     = "worca-poc/worca-worker"
  }
}

variable "worca_image_tag" {
  description = "Tag of the controller image; worker images are <tag>-<engine>."
  type        = string
  default     = "poc"
}

variable "worca_host" {
  description = "Public host name of Worca, e.g. worca.azure.example.com."
  type        = string
}

variable "argocd_host" {
  description = "Public host name of the Argo CD UI, e.g. argocd.azure.example.com."
  type        = string
}

variable "letsencrypt_email" {
  description = "Let's Encrypt account e-mail for expiry notices; empty registers without one (cert-manager renews on its own)."
  type        = string
  default     = ""
}

variable "letsencrypt_staging" {
  description = "Use Let's Encrypt's staging CA (untrusted certificates, generous limits) while trying things out."
  type        = bool
  default     = false
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

# --- Secrets: Key Vault secret names (worca-iac/secrets/azure-keyvault) -----------------------

variable "controller_env_secrets" {
  description = "Environment variables for the controller, each read from Key Vault secret controller-<NAME> (underscores as dashes)."
  type        = list(string)
  default     = ["CLAUDE_CODE_OAUTH_TOKEN"]
}

variable "worker_env_secrets" {
  description = "Environment variables for worker pods, each read from Key Vault secret worker-<NAME>. Keep GitHub tokens out: workers run agents."
  type        = list(string)
  default     = ["CLAUDE_CODE_OAUTH_TOKEN"]
}

# --- Add-on chart versions -------------------------------------------------------------------

variable "chart_versions" {
  type = object({
    argo_cd          = string
    alb_controller   = string
    cert_manager     = string
    external_secrets = string
  })
  default = {
    argo_cd          = "10.18.0"
    alb_controller   = "1.9.16"
    cert_manager     = "v1.21.3"
    external_secrets = "2.15.0"
  }
}
