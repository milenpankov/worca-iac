# One ACM certificate for both hosts, attached to the ALB (alb_annotations). Validated by DNS:
# automatically when route53_zone is set, otherwise add the records in output
# acm_validation_records at your DNS provider once. ACM renews it on its own.
resource "aws_acm_certificate" "this" {
  domain_name               = var.worca_host
  subject_alternative_names = [var.argocd_host]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = var.route53_zone == "" ? {} : {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o
  }

  zone_id         = local.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count = var.route53_zone == "" ? 0 : 1

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}
