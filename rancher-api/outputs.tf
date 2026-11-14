output "worca_url" {
  value = "https://${var.worca_host}"
}

output "argocd_url" {
  value = "https://${var.argocd_host}"
}

output "oidc_redirect_uri" {
  description = "Register this as a Web redirect URI of the OpenID Connect app registration."
  value       = "https://${var.worca_host}/oauth2/callback"
}

output "project_id" {
  value = local.project_id
}

output "namespaces" {
  value = local.namespaces
}

output "vault_entries" {
  description = "The KV v2 entries (mount/path) and the keys each must hold before Worca can start (README)."
  value = {
    "${var.vault.kv_mount}/${var.vault.auth_path}"   = ["client-secret", "cookie-secret"]
    "${var.vault.kv_mount}/${var.vault.controller}"  = ["CLAUDE_CODE_OAUTH_TOKEN", "GH_TOKEN (optional)", "..."]
    "${var.vault.kv_mount}/${var.vault.worker_path}" = ["CLAUDE_CODE_OAUTH_TOKEN"]
  }
}

output "kubeconfig_command" {
  description = "Writes a kubeconfig for this cluster through Rancher's proxy, with your Rancher token in RANCHER_TOKEN (chmod 600)."
  value       = "kubectl config set-cluster worca --server=${local.kube.host}${var.rancher_ca_file == "" ? "" : " --certificate-authority=${abspath(var.rancher_ca_file)} --embed-certs"} --kubeconfig=worca.kubeconfig && kubectl config set-credentials worca --token=\"$RANCHER_TOKEN\" --kubeconfig=worca.kubeconfig && kubectl config set-context worca --cluster=worca --user=worca --namespace=${local.namespaces.worca} --kubeconfig=worca.kubeconfig && kubectl config use-context worca --kubeconfig=worca.kubeconfig"
}

output "argocd_admin_password_command" {
  description = "Prints Argo CD's `admin` password, generated at install. Change it after the first login, then delete that Secret."
  value       = "kubectl -n ${local.namespaces.argocd} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
