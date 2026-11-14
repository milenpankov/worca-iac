output "vault_name" {
  description = "Use as key_vault_name in azure-aks/infra and azure-aks/platform."
  value       = azurerm_key_vault.this.name
}

output "resource_group" {
  description = "Use as key_vault_resource_group in azure-aks/infra and azure-aks/platform."
  value       = azurerm_resource_group.this.name
}

output "vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}
