# Both hosts: CNAMEs to the AGC frontend, in the Azure DNS zone (worca-iac/dns/azure).
resource "azurerm_dns_cname_record" "hosts" {
  for_each            = { worca = var.worca_host, argocd = var.argocd_host }
  name                = trimsuffix(each.value, ".${local.infra.dns_zone}")
  zone_name           = local.infra.dns_zone
  resource_group_name = local.infra.dns_resource_group
  ttl                 = 300
  record              = local.infra.agc_frontend_fqdn
}
