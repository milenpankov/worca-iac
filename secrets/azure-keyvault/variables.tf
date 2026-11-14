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
  description = "Prefix of the resource group and tag Project, so it is easy to find and remove."
  type        = string
  default     = "worca-poc"
}

variable "vault_name" {
  description = "Globally unique, 3-24 letters, digits and dashes (it becomes https://<vault_name>.vault.azure.net)."
  type        = string
}
