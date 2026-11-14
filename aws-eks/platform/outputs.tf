output "worca_url" {
  value = "https://${var.worca_host}"
}

output "argocd_url" {
  value = "https://${var.argocd_host}"
}

output "entra_redirect_uri" {
  description = "Register this as the Web redirect URI of Worca's Entra app registration."
  value       = "https://${var.worca_host}/oauth2/callback"
}

output "load_balancer_hostname" {
  description = "The ALB. CNAME both hosts to it unless route53_zone is set. Empty on the very first apply until the ALB exists: run apply again."
  value       = local.lb_hostname
}

output "acm_validation_records" {
  description = "Without route53_zone: add these CNAMEs at your DNS provider once; the ALB serves HTTPS after ACM has validated them."
  value = var.route53_zone != "" ? [] : [
    for o in aws_acm_certificate.this.domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ]
}

output "ssm_parameters" {
  description = "The SecureString parameters to create before Worca can start (README: Secrets)."
  value = sort(distinct(flatten([
    for secret, spec in local.secrets : [for k, p in spec.data : "${local.ssm_prefix}/${p}"]
  ])))
}

output "argocd_admin_password_command" {
  description = "Prints Argo CD's `admin` password, generated in the cluster at install (never in Terraform state). Change it after the first login, then delete that Secret."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
