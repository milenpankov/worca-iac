locals {
  tags = merge({
    Project     = "worca"
    Environment = var.environment
    Deployment  = var.name
    ManagedBy   = "terraform"
  }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = var.name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}

# Nodes. Pods get overlay addresses (Azure CNI overlay), so the subnet only holds nodes. The
# Microsoft.Storage service endpoint lets the nodes reach the NFS file share (storage.tf).
resource "azurerm_subnet" "nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 0)]

  service_endpoint {
    service = "Microsoft.Storage"
  }
}

# Application Gateway for Containers needs a subnet of its own (at least /24), delegated to it.
resource "azurerm_subnet" "agc" {
  name                 = "agc"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 8, 16)]

  delegation {
    name = "agc"
    service_delegation {
      name    = "Microsoft.ServiceNetworking/trafficControllers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
