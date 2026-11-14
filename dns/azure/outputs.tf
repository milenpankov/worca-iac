output "zone_name" {
  description = "Use as dns_zone in azure-aks/infra and azure-aks/platform."
  value       = azurerm_dns_zone.this.name
}

output "resource_group" {
  description = "Use as dns_resource_group in azure-aks/infra and azure-aks/platform."
  value       = azurerm_resource_group.this.name
}

output "name_servers" {
  description = "Add these as NS records for zone_name at the parent domain's DNS provider."
  value       = azurerm_dns_zone.this.name_servers
}

output "delegation" {
  description = "The NS records the parent domain needs, one per line."
  value       = join("\n", [for ns in azurerm_dns_zone.this.name_servers : "${var.zone_name}  NS  ${trimsuffix(ns, ".")}."])
}
