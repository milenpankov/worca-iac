variable "subscription_id" {
  description = "Azure subscription (az account show --query id -o tsv)."
  type        = string
}

variable "tenant_id" {
  description = "The subscription's Entra tenant (az account show --query tenantId -o tsv): pinned, so a login that sees several tenants never applies to the wrong one."
  type        = string
}

variable "location" {
  type    = string
  default = "germanywestcentral"
}

variable "name" {
  description = "Name of the cluster and prefix of everything created."
  type        = string
  default     = "worca-aks"
}

variable "environment" {
  type    = string
  default = "poc"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version; null takes the region's default."
  type        = string
  default     = null
}

variable "vnet_cidr" {
  type    = string
  default = "10.44.0.0/16"
}

variable "system_vm_size" {
  description = "The always-on node: Worca controller, oauth2-proxy, Argo CD, the ALB controller, cert-manager, External Secrets. 8 GB is the comfortable minimum."
  type        = string
  default     = "Standard_D2as_v5"
}

variable "worker_vm_size" {
  description = "Spot VM size for worker pods (2 vCPU / 8 GB: two workers)."
  type        = string
  default     = "Standard_D2as_v5"
}

variable "worker_max_nodes" {
  description = "Most worker nodes the autoscaler may start. 0 while no run is active."
  type        = number
  default     = 2
}

variable "cluster_admin_object_ids" {
  description = "Entra object ids (users, groups) given cluster-admin, besides whoever runs terraform apply."
  type        = list(string)
  default     = []
}

# --- The permanent roots this deployment uses ---

variable "acr_name" {
  description = "The registry from worca-iac/registry/acr (its name, not the login server)."
  type        = string
}

variable "acr_resource_group" {
  type    = string
  default = "worca-poc-acr"
}

variable "key_vault_name" {
  description = "The vault from worca-iac/secrets/azure-keyvault."
  type        = string
}

variable "key_vault_resource_group" {
  type    = string
  default = "worca-poc-secrets"
}

variable "dns_zone" {
  description = "The Azure DNS zone from worca-iac/dns/azure (e.g. azure.example.com): cert-manager answers Let's Encrypt there. Empty: no DNS identity."
  type        = string
  default     = ""
}

variable "dns_resource_group" {
  type    = string
  default = "worca-poc-dns"
}

variable "tags" {
  type    = map(string)
  default = {}
}
