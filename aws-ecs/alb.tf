# HTTPS in front of oauth2-proxy: an ALB with an ACM certificate, and (with route53_zone) the
# certificate's validation and the host's record.

data "aws_route53_zone" "this" {
  count = var.route53_zone == "" ? 0 : 1
  name  = var.route53_zone
}

resource "aws_acm_certificate" "this" {
  domain_name       = var.worca_host
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = var.route53_zone == "" ? {} : {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o
  }

  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

# Without route53_zone, the first apply waits here (up to 75 minutes) until you add the records in
# output acm_validation_records.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = var.route53_zone == "" ? null : [for r in aws_route53_record.acm_validation : r.fqdn]
}

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  # Worca's WebSockets stay open while a page is: the default 60 s would cut quiet ones.
  idle_timeout = 3600
}

resource "aws_lb_target_group" "worca" {
  name                 = "${var.name}-auth"
  port                 = 4180
  protocol             = "HTTP"
  target_type          = "instance" # the controller task uses the system instance's network
  vpc_id               = module.vpc.vpc_id
  deregistration_delay = 15

  health_check {
    path                = "/ping" # oauth2-proxy answers 200 without a session
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.worca.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_route53_record" "worca" {
  count   = var.route53_zone == "" ? 0 : 1
  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = var.worca_host
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}
