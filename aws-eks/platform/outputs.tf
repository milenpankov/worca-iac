output "worca_url" {
  value = "https://${var.worca_host}"
}

output "entra_redirect_uri" {
  description = "Register this as the app registration's Web redirect URI."
  value       = "https://${var.worca_host}/oauth2/callback"
}

output "load_balancer_hostname" {
  description = "Point worca_host here (CNAME) unless route53_zone_id is set. Empty on the very first apply until the NLB exists: run apply again."
  value       = local.lb_hostname
}

output "ssm_parameters" {
  description = "The SecureString parameters to create before Worca can start (README: Secrets)."
  value = flatten([
    for secret, spec in local.secrets : [for k in spec.keys : "${local.ssm_prefix}/${spec.path}/${k}"]
  ])
}

output "argocd_ui" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:443   # https://localhost:8080, user admin, password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
