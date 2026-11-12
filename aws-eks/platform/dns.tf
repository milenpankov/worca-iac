# The ALB the `worca` IngressGroup got (Argo CD's Ingress is in it, and Terraform knows that one).
# Point both hosts at it: here when a Route 53 zone is given, otherwise at your DNS provider
# (output load_balancer_hostname).
data "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}

locals {
  lb_hostname = try(data.kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, "")
}

resource "aws_route53_record" "hosts" {
  for_each = var.route53_zone_id == "" || local.lb_hostname == "" ? toset([]) : toset([var.worca_host, var.argocd_host])

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "CNAME"
  ttl     = 300
  records = [local.lb_hostname]
}
