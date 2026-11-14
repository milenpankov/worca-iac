# An Azure DNS zone for one subdomain of a domain whose DNS lives elsewhere. The deployments
# (azure-aks/platform) put their records in it, and cert-manager its DNS-01 challenges; it outlives
# them, so the delegation at the parent's DNS provider is set once. ~$0.50 a month.
locals {
  zone = "${var.zone_name}.${var.domain}"
  tags = { Project = var.name, ManagedBy = "terraform", Root = "worca-iac/dns/azure" }
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-dns"
  location = var.location
  tags     = local.tags
}

resource "azurerm_dns_zone" "this" {
  name                = local.zone
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}
