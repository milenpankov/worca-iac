# The Key Vault the deployment reads its secrets from, the Azure counterpart of SSM Parameter Store:
# kept across teardowns, so secrets are put once. Standard tier, no fee per secret: ~$0.03 per
# 10,000 reads. Access is Azure RBAC only: whoever applies this may manage secrets; the cluster's
# External Secrets identity gets read access from azure-aks/infra.
locals {
  tags = { Project = var.name, ManagedBy = "terraform", Root = "worca-iac/secrets/azure-keyvault" }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-secrets"
  location = var.location
  tags     = local.tags
}

resource "azurerm_key_vault" "this" {
  name                       = var.vault_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.tags
}

resource "azurerm_role_assignment" "officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
