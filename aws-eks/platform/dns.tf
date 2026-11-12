# The NLB Traefik's Service got. Point worca_host at it: here when a Route 53 zone is given,
# otherwise at your DNS provider (output load_balancer_hostname).
data "kubernetes_service_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = helm_release.traefik.namespace
  }
}

locals {
  lb_hostname = try(data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].hostname, "")
}

resource "aws_route53_record" "worca" {
  count = var.route53_zone_id == "" ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.worca_host
  type    = "CNAME"
  ttl     = 300
  records = [local.lb_hostname]
}
