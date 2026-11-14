# Workload Identity: one managed identity per add-on, federated with its Kubernetes service account,
# holding only the Azure roles that add-on needs. No secret anywhere.

locals {
  # name => { namespace, service account, roles: { key => { scope, role } } }
  workload_identities = merge({
    "external-secrets" = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      roles = {
        vault = { scope = data.azurerm_key_vault.this.id, role = "Key Vault Secrets User" }
      }
    }
    "alb-controller" = {
      namespace       = "azure-alb-system"
      service_account = "alb-controller-sa"
      roles = {
        agc    = { scope = azurerm_application_load_balancer.this.id, role = "AppGw for Containers Configuration Manager" }
        subnet = { scope = azurerm_subnet.agc.id, role = "Network Contributor" }
        nodes  = { scope = "/subscriptions/${var.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.this.node_resource_group}", role = "Reader" }
      }
    }
    }, var.dns_zone == "" ? {} : {
    "cert-manager" = {
      namespace       = "cert-manager"
      service_account = "cert-manager"
      roles = {
        dns = { scope = data.azurerm_dns_zone.this[0].id, role = "DNS Zone Contributor" }
      }
    }
  })

  workload_roles = merge([
    for id, w in local.workload_identities : { for k, r in w.roles : "${id}/${k}" => merge(r, { identity = id }) }
  ]...)
}

data "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group
}

data "azurerm_dns_zone" "this" {
  count               = var.dns_zone == "" ? 0 : 1
  name                = var.dns_zone
  resource_group_name = var.dns_resource_group
}

resource "azurerm_user_assigned_identity" "workload" {
  for_each            = local.workload_identities
  name                = "${var.name}-${each.key}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "workload" {
  for_each                  = local.workload_identities
  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.workload[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

resource "azurerm_role_assignment" "workload" {
  for_each             = local.workload_roles
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.workload[each.value.identity].principal_id
}
