output "worca_url" {
  value = "https://${var.worca_host}"
}

output "oidc_redirect_uri" {
  description = "Register this as a Web redirect URI of the OpenID Connect app registration."
  value       = "https://${var.worca_host}/oauth2/callback"
}

output "argocd_url_command" {
  description = "Prints Argo CD's URL (the operator's route)."
  value       = var.argocd.mode == "operator" ? "oc -n ${local.ns} get route ${var.argocd.instance_name}-server -o jsonpath='https://{.spec.host}{\"\\n\"}'" : "argocd.mode = helm: no Argo CD"
}

output "vault_entries" {
  description = "The KV v2 entries (mount/path) and the keys each must hold before Worca can start (README)."
  value = {
    "${var.vault.kv_mount}/${var.vault.auth_path}"       = ["client-secret", "cookie-secret"]
    "${var.vault.kv_mount}/${var.vault.controller_path}" = ["CLAUDE_CODE_OAUTH_TOKEN", "GH_TOKEN (optional)", "..."]
    "${var.vault.kv_mount}/${var.vault.worker_path}"     = ["CLAUDE_CODE_OAUTH_TOKEN"]
  }
}

output "vault_kubernetes_auth_commands" {
  description = "For vault.auth_method = kubernetes: what to run against Vault (with VAULT_ADDR, VAULT_NAMESPACE and a token set) once, after the first apply. Reads the reviewer token with your oc login."
  value = local.kubernetes_auth ? join("\n", [
    "REVIEWER_JWT=$(oc -n ${local.ns} get secret ${var.vault.service_account}-token -o jsonpath='{.data.token}' | base64 -d)",
    "vault auth enable -path=${var.vault.auth_mount} kubernetes   # once per Vault namespace",
    "vault write auth/${var.vault.auth_mount}/config token_reviewer_jwt=\"$REVIEWER_JWT\" kubernetes_host=${var.api_url} kubernetes_ca_cert=@<api-ca.pem> disable_issuer_verification=true",
    "vault policy write ${var.vault.role} - <<'EOF'\npath \"${var.vault.kv_mount}/data/${dirname(var.vault.auth_path)}/*\" { capabilities = [\"read\"] }\nEOF",
    "vault write auth/${var.vault.auth_mount}/role/${var.vault.role} bound_service_account_names=${var.vault.service_account} bound_service_account_namespaces=${local.ns} audience=https://kubernetes.default.svc token_policies=${var.vault.role} token_ttl=1h",
  ]) : "vault.auth_method = approle"
}
