# Worca on a Rancher-managed cluster

Worca with its controller/worker topology on an existing Kubernetes cluster that Rancher manages,
through the Rancher API: no cloud account, no infrastructure to create. One Terraform root and one
Rancher API token do everything:

| What | How |
|---|---|
| A Rancher project with a quota and container defaults (or an existing project) | `rancher2_project` |
| Three namespaces in it, each with its own quota: `<prefix>argocd`, `<prefix>vault-secrets-operator`, `<prefix>worca` | `rancher2_namespace` |
| An image pull secret in each, for the internal registry every image comes from | Kubernetes Secret |
| The Vault Secrets Operator: Worca's secrets from Vault or OpenBao, logged in with an AppRole | Helm |
| Argo CD (release `worca-argocd`) and its Ingress | Helm |
| The Argo CD Application that deploys the Worca chart from git, plus the VSO objects | `charts/bootstrap` |

```
            ingress controller (class nginx, the cluster's wildcard certificate)
               │                                  │
      worca.apps.example.com             argocd-worca.apps.example.com
               │                                  │
  <prefix>worca: oauth2-proxy ── controller   <prefix>argocd: Argo CD ── git (worca-cc chart)
                                    │  creates
                               worker pods (one per run / chat thread)
                                    │
        shared ReadWriteMany volume (/worca, /projects) · SQLite on its own ReadWriteOnce volume

  <prefix>vault-secrets-operator: VSO ── Vault / OpenBao KV ──► Secrets worca-auth, worca-secrets,
                                                               worca-worker-credentials
```

The Kubernetes API is reached through Rancher's proxy (`<rancher_url>/k8s/clusters/<cluster_id>`)
with the same token, so there is no kubeconfig file and Rancher mints no new token per run.

## What the cluster must offer

- **A Rancher account that is cluster owner** on the cluster. Project member is not enough: Argo CD
  and the Vault Secrets Operator install CRDs and ClusterRoles. An API key of that account
  (`token-xxxxx:secret`), with an expiry you track.
- **An ingress controller** and DNS that already sends Worca's and Argo CD's host names to it
  (usually a wildcard for the cluster's domain), with a certificate for them: the controller's
  default (wildcard) certificate, or a TLS Secret you name in `tls_secret_name`.
- **A ReadWriteMany storage class** (NFS, CephFS, Longhorn RWX, ...) for the volume controller and
  workers share, and a ReadWriteOnce class for SQLite (never NFS: SQLite's locks need a local file
  system).
- **Egress** from pods to the model API, GitHub and your identity provider: directly or through an
  HTTP proxy (`http_proxy`, `no_proxy`).
- **No Vault Secrets Operator already running.** Two operators would both reconcile every
  VaultStaticSecret. If the cluster has one, set `install_vault_secrets_operator = false`; this
  root's VaultConnection, VaultAuth and VaultStaticSecrets work with it.
- **Another Argo CD on the cluster is fine:** this one has its own release name, ClusterRoles and
  installation ID. If that Argo CD installed the CRDs already, set `argocd_install_crds = false`
  (Helm refuses CRDs another release owns).

## 1. Mirror the images

Every image comes from one registry (`registry`) with one pull secret. Worca's own images are
built from worca-cc and pushed there; the others are copies of the public ones. The tags are what
the pinned chart versions use:

| `images.*` | Public image | Tag |
|---|---|---|
| `worca_controller` | built from worca-cc (`docker/Dockerfile`, target `controller`) | `worca_image_tag` |
| `worca_worker` | built from worca-cc (`docker/Dockerfile`, target `worker`) | `<worca_image_tag>-claude` (one per engine) |
| `oauth2_proxy` | `quay.io/oauth2-proxy/oauth2-proxy` | `v7.15.6` |
| `argocd` | `quay.io/argoproj/argocd` | `v3.6.1` (argo-cd chart 10.18.0) |
| `redis` | `ecr-public.aws.com/docker/library/redis` | `8.6.4-alpine` |
| `vso` | `docker.io/hashicorp/vault-secrets-operator` | `1.6.2` |
| `kube_rbac_proxy` | `quay.io/brancz/kube-rbac-proxy` | `v0.18.1` |

With [crane](https://github.com/google/go-containerregistry/blob/main/cmd/crane/README.md), logged
in to the registry (`crane auth login registry.example.com -u ...`):

```bash
R=registry.example.com/mirror
crane copy quay.io/oauth2-proxy/oauth2-proxy:v7.15.6               $R/oauth2-proxy/oauth2-proxy:v7.15.6
crane copy quay.io/argoproj/argocd:v3.6.1                          $R/argoproj/argocd:v3.6.1
crane copy ecr-public.aws.com/docker/library/redis:8.6.4-alpine    $R/docker/library/redis:8.6.4-alpine
crane copy docker.io/hashicorp/vault-secrets-operator:1.6.2        $R/hashicorp/vault-secrets-operator:1.6.2
crane copy quay.io/brancz/kube-rbac-proxy:v0.18.1                  $R/brancz/kube-rbac-proxy:v0.18.1
```

When you bump `chart_versions`, check the tags again: `helm template` the chart and grep `image:`.

If Helm itself cannot reach the public chart repositories from where you run Terraform, point
`chart_repositories` at a mirror.

## 2. Put the secrets in Vault

Three KV v2 entries, one per Kubernetes Secret. Each entry's keys become that Secret's keys:

| Entry (`vault.*`, under `vault.kv_mount`) | Keys | Secret |
|---|---|---|
| `auth_path` (default `worca/auth`) | `client-secret` (the app registration's), `cookie-secret` | `worca-auth` (oauth2-proxy) |
| `controller` (default `worca/controller`) | `CLAUDE_CODE_OAUTH_TOKEN`, `GH_TOKEN`, ... any controller variable | `worca-secrets` |
| `worker_path` (default `worca/worker`) | `CLAUDE_CODE_OAUTH_TOKEN` (keep GitHub tokens out: workers run agents) | `worca-worker-credentials` |

With the `vault` CLI (`bao` for OpenBao takes the same arguments; add `-namespace=...` for a
namespace):

```bash
vault kv put -mount=kv worca/auth \
  client-secret=- cookie-secret="$(openssl rand -base64 32 | tr -- '+/' '-_')" < client-secret.txt
vault kv put -mount=kv worca/controller CLAUDE_CODE_OAUTH_TOKEN=- < claude-token.txt
vault kv put -mount=kv worca/worker     CLAUDE_CODE_OAUTH_TOKEN=- < claude-token.txt
```

(`key=-` reads that one value from stdin, so nothing lands in your shell history.)

An AppRole that may read exactly these three entries:

```bash
vault policy write worca-read - <<'EOF'
path "kv/data/worca/*" { capabilities = ["read"] }
EOF
vault write auth/approle/role/worca token_policies=worca-read token_ttl=1h token_max_ttl=4h
vault read  -field=role_id  auth/approle/role/worca/role-id          # -> vault.role_id in tfvars
vault write -field=secret_id -f auth/approle/role/worca/secret-id    # -> TF_VAR_vault_approle_secret_id
```

The secret ID becomes a Kubernetes Secret (`vault-approle`) that VSO logs in with, so it is also in
this root's Terraform state: keep the state local and private (the repository ignores it).

Changing a value in Vault reaches the cluster within `vault.refresh` (default 1h); VSO then
restarts the controller or oauth2-proxy. Workers read theirs when they start.

## 3. Configure and apply

```bash
cd rancher-api
cp terraform.tfvars.example terraform.tfvars   # fill in; it is gitignored
export TF_VAR_rancher_token=token-xxxxx:...
export TF_VAR_registry_username=... TF_VAR_registry_password=...
export TF_VAR_vault_approle_secret_id=...
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Register `terraform output -raw oidc_redirect_uri` as a Web redirect URI of the OpenID Connect app
registration. For Microsoft Entra ID, the example in `terraform.tfvars.example` uses
`preferred_username` as the e-mail and app roles as teams.

## 4. Check it

```bash
eval "$(terraform output -raw kubeconfig_command)"     # needs RANCHER_TOKEN=$TF_VAR_rancher_token
export KUBECONFIG=$PWD/worca.kubeconfig
kubectl get vaultstaticsecrets                         # all three: no error, secretMAC set
kubectl -n "$(terraform output -json namespaces | jq -r .argocd)" get applications
kubectl get pods,pvc -w                                # the controller, oauth2-proxy; a worker per chat
```

Then open `terraform output -raw worca_url`, sign in and start a chat: a worker pod appears in the
same namespace and goes when it is idle.

Argo CD: `terraform output -raw argocd_url`, user `admin`, password from
`eval "$(terraform output -raw argocd_admin_password_command)"`. Change it, then delete
`argocd-initial-admin-secret`.

## Sizing the quotas

Every container needs requests and limits when its namespace has a quota. The charts set them here,
and the project's container defaults (`container_default_resources`) cover any that do not. The
`worca` namespace's quota must hold the controller (2 CPU / 3 Gi limits), oauth2-proxy and
`worker.max_workers` workers at `worker.limits_*`. With the defaults: 2 + 0.5 + 2 × 2 CPU and
3 + 0.25 + 2 × 4 Gi, within the default 10 CPU / 20 Gi. A worker that does not fit the quota stays
unscheduled until the controller's pending timeout gives up on it: raise the quota with
`max_workers`.

With `existing_project_id`, the project's own quota applies. When that project has no quota, set
`namespace_quotas = {}` (Rancher refuses namespace quotas there).

## Tear down

```bash
terraform destroy
```

Argo CD's Application goes first and deletes Worca, then the add-ons, then the namespaces with
their volumes (the data goes with them), then the project. The images in the registry and the
entries in Vault stay.
