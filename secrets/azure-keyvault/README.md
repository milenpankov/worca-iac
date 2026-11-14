# Azure Key Vault for the deployment's secrets

The Azure counterpart of SSM Parameter Store: [azure-aks](../../azure-aks) reads Worca's secrets
from it through External Secrets (Workload Identity, read-only), and never through Terraform or its
state. Kept across teardowns, so secrets are put once.

- **Cost:** Standard tier, no fee per secret, ~$0.03 per 10,000 reads.
- **Access:** Azure RBAC. Whoever applies this root gets Key Vault Secrets Officer.
- **Names:** letters, digits and dashes only, so an environment variable's `_` becomes `-`
  (`CLAUDE_CODE_OAUTH_TOKEN` -> `CLAUDE-CODE-OAUTH-TOKEN`).

## Set up once

```bash
az login
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

## The secrets

```bash
V=$(terraform output -raw vault_name)
az keyvault secret set --vault-name $V --name auth-tenant-id     --value '<Directory (tenant) ID>'
az keyvault secret set --vault-name $V --name auth-client-id     --value '<Application (client) ID>'
az keyvault secret set --vault-name $V --name auth-client-secret --value '<Entra client secret>'
az keyvault secret set --vault-name $V --name auth-cookie-secret --value "$(openssl rand -base64 32 | tr -- '+/' '-_')"
az keyvault secret set --vault-name $V --name controller-CLAUDE-CODE-OAUTH-TOKEN --value '<token>'
az keyvault secret set --vault-name $V --name worker-CLAUDE-CODE-OAUTH-TOKEN     --value '<token>'
```

The tenant and client ids are not secret (every sign-in URL shows them), just kept out of git.

## Remove

`terraform destroy` deletes and purges the vault with its secrets.
