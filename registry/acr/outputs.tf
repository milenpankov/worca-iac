output "registry" {
  description = "The login server: tag images <registry>/<name>/worca:<tag>."
  value       = azurerm_container_registry.this.login_server
}

output "registry_id" {
  description = "azure-aks/infra grants the cluster AcrPull on it (acr_name, acr_resource_group)."
  value       = azurerm_container_registry.this.id
}

output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "repositories" {
  value = {
    controller = "${var.name}/worca"
    worker     = "${var.name}/worca-worker"
  }
}
