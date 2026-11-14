# Worca on Azure AKS

The same Worca deployment as [aws-eks](../aws-eks), on Azure:
- **Controller:** one controller pod that starts a worker pod per run and per chat thread
  (`executor: kubernetes`).
- **Sign-in:** Microsoft Entra ID.
- **Secrets:** Azure Key Vault.
- **Deployment:** Argo CD deploys Worca from its git branch.

```
                                       Entra ID (Worca's sign-in)
                                           ▲
 browser ──https──► Application Gateway for Containers (Let's Encrypt via cert-manager, DNS-01)
                     ├─ worca_host  ──► oauth2-proxy ──► worca controller ──(pods API)──► worker pods
                     │                                   │  SQLite on Premium SSD   (spot nodes, 0..N)
                     │                                   └── Azure Files NFS (shared /worca, /projects) ──┘
                     └─ argocd_host ──► Argo CD (own admin login) ── git: worca-cc deploy/helm/worca
 External Secrets ── Key Vault (Workload Identity) ──► worca-auth, worca-secrets, worca-worker-credentials
```

| AWS EKS | Azure AKS |
|---|---|
| EKS control plane ($73/month) | AKS Free tier ($0; Standard with an uptime SLA ~$73) |
| on-demand system node + spot node group, Cluster Autoscaler | system pool + spot user pool 0..N, AKS's own cluster autoscaler |
| EFS (shared files) | Azure Files premium NFS (100 GiB minimum share) |
| EBS gp3 (SQLite) | Azure managed disk, Premium SSD (`managed-csi-premium`) |
| ALB + ACM | Application Gateway for Containers + cert-manager (Let's Encrypt) |
| SSM Parameter Store, Pod Identity | Key Vault ([secrets/azure-keyvault](../secrets/azure-keyvault)), Workload Identity |
| ECR ([registry/ecr](../registry/ecr)) | ACR ([registry/acr](../registry/acr)) |
| Route 53 zone ([dns/route53](../dns/route53)) | Azure DNS zone ([dns/azure](../dns/azure)) |

Two Terraform roots, applied in order, each with its own state:

| Root | What it creates |
|---|---|
| [infra/](infra) | The resource group and VNet. AKS: Free tier, Azure CNI overlay, Entra ID with Azure RBAC, local accounts off, OIDC issuer and Workload Identity. A system pool (1 node) and a spot workers pool (0..N, tainted). The Application Gateway for Containers with its delegated subnet and frontend. AcrPull for the kubelet. Managed identities for External Secrets (Key Vault read), the ALB controller (that AGC), and cert-manager (that DNS zone). |
| [platform/](platform) | The ALB controller, cert-manager, External Secrets and Argo CD, then [charts/bootstrap](platform/charts/bootstrap): the `azurefile-nfs` storage class, the Let's Encrypt issuer, the Key Vault store and ExternalSecrets, AGC health checks, and the Argo CD Application with [values/worca-poc.yaml](platform/values/worca-poc.yaml). Also the hosts' CNAMEs to the AGC frontend. |

## Before you start

- **Tools:** Terraform 1.9 or newer, Azure CLI (`az login`), Helm, and Docker for the images. For kubectl,
  `kubelogin` (`az aks install-cli`).
- **Set up once:** the permanent roots, in this order:
  1. [dns/azure](../dns/azure): the zone, e.g. `azure.example.com`, delegated from the parent domain.
  2. [registry/acr](../registry/acr): the images, pushed there.
  3. [secrets/azure-keyvault](../secrets/azure-keyvault): the vault and its secrets (`auth-tenant-id`,
     `auth-client-id`, `auth-client-secret`, `auth-cookie-secret`, `controller-CLAUDE-CODE-OAUTH-TOKEN`,
     `worker-CLAUDE-CODE-OAUTH-TOKEN`).
- **Entra app registration:** add the Web redirect URI `https://<worca_host>/oauth2/callback`.
- **Resource providers** registered in the subscription (once):
  ```bash
  for p in Microsoft.ContainerService Microsoft.ServiceNetworking Microsoft.Network Microsoft.NetworkFunction Microsoft.Storage Microsoft.KeyVault Microsoft.ContainerRegistry; do az provider register --namespace $p; done
  ```

## Deploy

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # subscription, registry, vault, zone
terraform init && terraform apply              # ~10 minutes
$(terraform output -raw kubeconfig_command)

cd ../platform
cp terraform.tfvars.example terraform.tfvars   # hosts
terraform init && terraform apply              # ~5 minutes; the certificates a few more
```

Argo CD then syncs Worca:

```bash
kubectl -n argocd get applications
kubectl -n worca get pods,ingress,certificate,externalsecret
```

Then check it:
- `https://<argocd_host>`: `admin`, password from `terraform output -raw argocd_admin_password_command`.
  Change it, then delete `argocd-initial-admin-secret`.
- `https://<worca_host>`: Entra sign-in, then Worca. Start a chat: a worker pod waits, AKS starts a spot
  node (a few minutes from zero), the reply follows.

## Tear down

```bash
cd platform && terraform destroy
cd ../infra && terraform destroy
```

Destroy `platform` first, so Argo CD removes Worca and the ALB controller cleans up the AGC
configuration. What stays: the images, the DNS zone and the vault with its secrets.

## Cost (Germany West Central, approximate, per month)

| Item | ~ |
|---|---|
| AKS control plane, Free tier | $0 |
| System node Standard_D2as_v5, 24/7 (+ OS disk) | $75–85 |
| Worker spot nodes, ~2 h/day | $1–3 |
| Application Gateway for Containers (one frontend, one association, light traffic) | $20–30 |
| Azure Files premium NFS, 100 GiB provisioned | $18–20 |
| Premium SSD 8 GiB (database) | $2 |
| Standard Load Balancer + public IP (AKS outbound) | $4–8 |
| ACR Basic (kept), DNS zone (kept), Key Vault (kept) | ~$6 |
| **Total** | **≈ $130–155** |

Model tokens are extra.

## Known limits

- **One controller.** The SQLite disk is zonal: losing the system node pauses runs until it is
  replaced.
- **The API server is public**, behind Entra ID with Azure RBAC. Add `api_server_access_profile` with your
  addresses to restrict it.
- **WebSockets:** AGC passes them through. If quiet sessions drop, add a RoutePolicy with a longer
  timeout.
