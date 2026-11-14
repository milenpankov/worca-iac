terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
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

# The cluster comes from the infra root's state (local file in the PoC).
data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = var.infra_state_path
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs

  # An Entra token for the AKS API (Azure RBAC; local accounts are off), from your az login on every
  # call: no credential in state or kubeconfig. 6dae42f8-... is the AKS AAD server application.
  kube_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "az"
    args = ["account", "get-access-token", "--tenant", local.infra.tenant_id, "--resource", "6dae42f8-4368-4678-94ff-3960e28e3630", "--output", "json",
    "--query", "{apiVersion:'client.authentication.k8s.io/v1beta1',kind:'ExecCredential',status:{token:accessToken}}"]
  }
}

provider "azurerm" {
  subscription_id = local.infra.subscription_id
  tenant_id       = local.infra.tenant_id
  features {}
}

provider "kubernetes" {
  host                   = local.infra.cluster_host
  cluster_ca_certificate = base64decode(local.infra.cluster_ca_certificate)
  exec {
    api_version = local.kube_exec.api_version
    command     = local.kube_exec.command
    args        = local.kube_exec.args
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.infra.cluster_host
    cluster_ca_certificate = base64decode(local.infra.cluster_ca_certificate)
    exec                   = local.kube_exec
  }
}
