# A Route 53 hosted zone for one subdomain of a domain whose DNS lives elsewhere. The deployments
# (aws-eks/platform) find it by name and put their records in it; it outlives them, so the
# delegation at the parent's DNS provider is set once. $0.50 a month.
locals {
  zone = "${var.zone_name}.${var.domain}"
}

resource "aws_route53_zone" "this" {
  name    = local.zone
  comment = "${var.name}: delegated from ${var.domain}"

  # destroy removes the zone even with records the deployments left behind.
  force_destroy = true
}
