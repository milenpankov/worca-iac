# The ALB the `worca` IngressGroup got (Argo CD's Ingress is in it, and Terraform knows that one).
# Point both hosts at it: here when a Route 53 zone is given (alias records, which also work at a
# zone apex), otherwise at your DNS provider (output load_balancer_hostname).
data "aws_route53_zone" "this" {
  count = var.route53_zone == "" ? 0 : 1
  name  = var.route53_zone
}

data "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}

# The hosted zone id of ALBs in this region, for alias records.
data "aws_lb_hosted_zone_id" "alb" {}

locals {
  zone_id     = try(data.aws_route53_zone.this[0].zone_id, "")
  lb_hostname = try(data.kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, "")
}

resource "aws_route53_record" "hosts" {
  for_each = local.zone_id == "" || local.lb_hostname == "" ? toset([]) : toset([var.worca_host, var.argocd_host])

  zone_id = local.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = local.lb_hostname
    zone_id                = data.aws_lb_hosted_zone_id.alb.id
    evaluate_target_health = false
  }
}
