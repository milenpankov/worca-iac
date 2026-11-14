# AKS on the Free tier (no control-plane fee; Standard adds an uptime SLA for ~$73/month).
#   system   one on-demand node: the controller, oauth2-proxy and the add-ons
#   workers  spot nodes, 0..worker_max_nodes, tainted: only worker pods (they tolerate the taints)
# Sign-in to the API is Entra ID with Azure RBAC; local accounts are off, so no static kubeconfig
# exists. Workload Identity gives the add-ons their Azure roles (identities.tf).

data "azurerm_client_config" "current" {}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"
  node_resource_group = "${var.name}-nodes"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  local_account_disabled    = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  default_node_pool {
    name                        = "system"
    vm_size                     = var.system_vm_size
    node_count                  = 1
    vnet_subnet_id              = azurerm_subnet.nodes.id
    os_disk_type                = "Managed"
    os_disk_size_gb             = 64
    temporary_name_for_rotation = "systemtmp"
    node_labels                 = { "worca.dev/pool" = "system" }

    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Node pools as declared here, scaled by the cluster autoscaler (not node auto-provisioning).
  node_provisioning_profile {
    mode = "Manual"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  storage_profile {
    disk_driver_enabled = true
    file_driver_enabled = true
  }

  # Worker nodes go 5 minutes after their last worker pod; pods with emptyDir (/tmp) do not keep
  # a node.
  auto_scaler_profile {
    expander                      = "least-waste"
    scale_down_unneeded           = "5m"
    scale_down_delay_after_add    = "5m"
    skip_nodes_with_local_storage = false
    balance_similar_node_groups   = true
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [default_node_pool[0].upgrade_settings]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "workers" {
  name                  = "workers"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.worker_vm_size
  vnet_subnet_id        = azurerm_subnet.nodes.id
  os_disk_type          = "Managed"
  os_disk_size_gb       = 64

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1 # up to the on-demand price: evicted for capacity, never for price

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = var.worker_max_nodes
  node_count           = 0

  node_labels = { "worca.dev/pool" = "workers" }
  # AKS adds the spot taint itself; listed so Terraform does not see a change.
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule",
    "worca.dev/worker=true:NoSchedule",
  ]

  tags = local.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

# Whoever applies (and cluster_admin_object_ids): cluster-admin through Azure RBAC.
resource "azurerm_role_assignment" "cluster_admin" {
  for_each             = toset(concat([data.azurerm_client_config.current.object_id], var.cluster_admin_object_ids))
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

# The VNet is ours, not AKS's: the cluster's identity needs Network Contributor on it. The Azure
# Files CSI driver sets the nodes subnet's storage service endpoint and network rule for the NFS
# share, and the cloud provider manages the load balancer's NICs there.
resource "azurerm_role_assignment" "cluster_network" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

# Image pulls from the registry (registry/acr) with the kubelet's identity.
data "azurerm_container_registry" "this" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                            = data.azurerm_container_registry.this.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
