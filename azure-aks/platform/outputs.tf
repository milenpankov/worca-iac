output "worca_url" {
  value = "https://${var.worca_host}"
}

output "argocd_url" {
  value = "https://${var.argocd_host}"
}

output "entra_redirect_uri" {
  description = "Register this as a Web redirect URI of Worca's Entra app registration."
  value       = "https://${var.worca_host}/oauth2/callback"
}

output "key_vault_secrets" {
  description = "The Key Vault secrets to set before Worca can start (README)."
  value = sort(concat(["auth-tenant-id", "auth-client-id", "auth-client-secret", "auth-cookie-secret"],
  flatten([for s in ["worca-secrets", "worca-worker-credentials"] : values(local.secrets[s].data)])))
}

output "argocd_admin_password_command" {
  description = "Prints Argo CD's `admin` password, generated in the cluster at install. Change it after the first login, then delete that Secret."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
