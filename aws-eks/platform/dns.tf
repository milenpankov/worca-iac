# The ALB of the `worca` IngressGroup, as Argo CD's Ingress reports it (addons.tf). Point both
# hosts at it: here when a Route 53 zone is given (alias records, which also work at a zone apex),
# otherwise at your DNS provider (output load_balancer_hostname).
data "aws_route53_zone" "this" {
  count = var.route53_zone == "" ? 0 : 1
  name  = var.route53_zone
}

# The hosted zone id of ALBs in this region, for alias records.
data "aws_lb_hosted_zone_id" "alb" {}

locals {
  zone_id     = try(data.aws_route53_zone.this[0].zone_id, "")
  lb_hostname = try(kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, "")
}

resource "aws_route53_record" "hosts" {
  for_each = var.route53_zone == "" ? toset([]) : toset([var.worca_host, var.argocd_host])

  zone_id = local.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = local.lb_hostname
    zone_id                = data.aws_lb_hosted_zone_id.alb.id
    evaluate_target_health = false
  }
}
