terraform {
  required_version = ">= 1.9"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
  }
}

# The cluster's API with a bearer token: a service account of your project that holds `admin`
# there (README), or your own `oc whoami -t` (expires within a day). Nothing outside the project
# is touched unless a variable says so (grant_scc, create_auth_delegator_binding).
locals {
  kube = {
    host                   = var.api_url
    token                  = var.token
    cluster_ca_certificate = var.ca_file == "" ? null : file(var.ca_file)
    insecure               = var.insecure_skip_tls_verify
  }
}

provider "kubernetes" {
  host                   = local.kube.host
  token                  = local.kube.token
  cluster_ca_certificate = local.kube.cluster_ca_certificate
  insecure               = local.kube.insecure
}

provider "helm" {
  kubernetes = local.kube
}
