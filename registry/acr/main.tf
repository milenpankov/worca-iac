# The container registry for Worca's images, kept apart from the deployment: a teardown leaves the
# images, and the next bring-up pulls them without building again. Basic tier: ~$5 a month with
# 10 GB included. Repositories appear on the first push: <name>/worca and <name>/worca-worker.
locals {
  tags = { Project = var.name, ManagedBy = "terraform", Root = "worca-iac/registry/acr" }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-acr"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_registry" "this" {
  name                = var.registry_name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false # pushes with your Entra login (az acr login), pulls with the cluster's identity
  tags                = local.tags
}

# Whoever applies this may push (az acr login + docker push).
resource "azurerm_role_assignment" "push" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}
