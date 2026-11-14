terraform {
  required_version = ">= 1.9"

  required_providers {
    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 8.0"
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

# One Rancher API token for everything: the Rancher API (project, namespaces) and the cluster's
# Kubernetes API through Rancher's proxy (<rancher_url>/k8s/clusters/<cluster_id>), which accepts
# any valid Rancher token. No kubeconfig file, and Rancher mints no extra token per run.
locals {
  rancher_url = trimsuffix(trimsuffix(var.rancher_url, "/"), "/v3")
  rancher_ca  = var.rancher_ca_file == "" ? null : file(var.rancher_ca_file)

  kube = {
    host                   = "${local.rancher_url}/k8s/clusters/${var.cluster_id}"
    token                  = var.rancher_token
    cluster_ca_certificate = local.rancher_ca
  }
}

provider "rancher2" {
  api_url   = local.rancher_url
  token_key = var.rancher_token
  ca_certs  = local.rancher_ca
}

provider "kubernetes" {
  host                   = local.kube.host
  token                  = local.kube.token
  cluster_ca_certificate = local.kube.cluster_ca_certificate
}

provider "helm" {
  kubernetes = local.kube
}
