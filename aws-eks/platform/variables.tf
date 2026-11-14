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
  description = "ECR repositories of the controller and worker images (worca-iac/registry/ecr), in this account and region."
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
  description = "Tag of the controller image in ECR; worker images are <tag>-<engine> (README: Images)."
  type        = string
  default     = "poc"
}

variable "worca_host" {
  description = "Public host name of Worca, e.g. worca.example.com. Point it at the ALB (output load_balancer_hostname) or set route53_zone."
  type        = string
}

variable "argocd_host" {
  description = "Public host name of the Argo CD UI, e.g. argocd.example.com. Same ALB, same certificate."
  type        = string
}

variable "route53_zone" {
  description = "Optional: the name of the Route 53 hosted zone both hosts are in (e.g. from worca-iac/dns/route53). The certificate's validation records and alias records to the ALB are created there."
  type        = string
  default     = ""
}

variable "mock_mode" {
  description = "WORCA_MOCK=1: pipelines run without model calls (no token spend). For the first end-to-end check."
  type        = bool
  default     = false
}

variable "timezone" {
  type    = string
  default = "Europe/Berlin"
}

# --- Secrets: names of SSM parameters under /worca/<environment>/ ----------------------------

variable "controller_env_secrets" {
  description = "Environment variables for the controller, each read from SSM /worca/<env>/controller/<NAME> (SecureString)."
  type        = list(string)
  default     = ["CLAUDE_CODE_OAUTH_TOKEN"]
}

variable "worker_env_secrets" {
  description = "Environment variables for worker pods, each read from SSM /worca/<env>/worker/<NAME>. Keep GitHub tokens out: workers run agents."
  type        = list(string)
  default     = ["CLAUDE_CODE_OAUTH_TOKEN"]
}

# --- Add-on chart versions -------------------------------------------------------------------

variable "chart_versions" {
  type = object({
    argo_cd                      = string
    aws_load_balancer_controller = string
    external_secrets             = string
    cluster_autoscaler           = string
  })
  default = {
    argo_cd                      = "10.18.0"
    aws_load_balancer_controller = "3.6.2"
    external_secrets             = "2.15.0"
    cluster_autoscaler           = "9.60.0"
  }
}

variable "cluster_autoscaler_image_tag" {
  description = "Cluster Autoscaler's minor version should match the cluster's Kubernetes minor."
  type        = string
  default     = "v1.35.3"
}
