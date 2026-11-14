# Application Gateway for Containers: the managed layer-7 load balancer in front of Worca and
# Argo CD (the counterpart of the ALB on EKS). Made here ("bring your own"), so Terraform owns its
# lifetime; the ALB controller in the cluster (platform) programs it from the Ingresses that name
# it. One frontend, one public host name; both hosts are CNAMEs to it.
resource "azurerm_application_load_balancer" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_application_load_balancer_subnet_association" "this" {
  name                         = "${var.name}-agc"
  application_load_balancer_id = azurerm_application_load_balancer.this.id
  subnet_id                    = azurerm_subnet.agc.id
  tags                         = local.tags
}

resource "azurerm_application_load_balancer_frontend" "this" {
  name                         = "public"
  application_load_balancer_id = azurerm_application_load_balancer.this.id
  tags                         = local.tags
}
