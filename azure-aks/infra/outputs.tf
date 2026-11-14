output "subscription_id" {
  value = var.subscription_id
}

output "location" {
  value = var.location
}

output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "cluster_host" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive = true
}

output "kubeconfig_command" {
  description = "kubectl access (needs kubelogin: az aks install-cli)."
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --overwrite-existing && kubelogin convert-kubeconfig -l azurecli"
}

output "tenant_id" {
  value = var.tenant_id
}

output "agc_id" {
  value = azurerm_application_load_balancer.this.id
}

output "agc_frontend" {
  value = azurerm_application_load_balancer_frontend.this.name
}

output "agc_frontend_fqdn" {
  description = "The public host name both hosts are CNAMEs to."
  value       = azurerm_application_load_balancer_frontend.this.fully_qualified_domain_name
}

output "workload_identity_client_ids" {
  value = { for k, v in azurerm_user_assigned_identity.workload : k => v.client_id }
}

output "key_vault_uri" {
  value = data.azurerm_key_vault.this.vault_uri
}

output "key_vault_name" {
  value = var.key_vault_name
}

output "key_vault_resource_group" {
  value = var.key_vault_resource_group
}

output "acr_login_server" {
  value = data.azurerm_container_registry.this.login_server
}

output "dns_zone" {
  value = var.dns_zone
}

output "dns_resource_group" {
  value = var.dns_resource_group
}
