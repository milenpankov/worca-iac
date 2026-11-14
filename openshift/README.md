# Worca on OpenShift

Worca with its controller/worker topology in one existing OpenShift project, set up by
Terraform with nothing but project rights: no cluster-admin, no CRDs or operators of its own.
It uses what OpenShift clusters usually offer — the OpenShift GitOps operator, the Vault Secrets
Operator, the router — and everything that differs between clusters is a variable.

| What | How |
|---|---|
| An image pull secret for the registry the images come from (optional) | Kubernetes Secret |
| Service accounts: the workers', and the Vault login's (kubernetes auth) | Terraform |
| Optional, with cluster rights: an SCC for Worca's accounts, auth-delegator for the Vault login | `grant_scc`, `create_auth_delegator_binding` |
| The shared claim, when it must be made before the chart (statically provisioned NFS) | `storage.shared_precreate` |
| An Argo CD instance of the OpenShift GitOps operator, signed in through OpenShift | `charts/argocd` |
| The Vault Secrets Operator's login and the three Secrets Worca reads; platform-specific objects | `charts/bootstrap` (`extra_manifests`) |
| Worca: an Argo CD Application that follows a branch, or a plain Helm release (`argocd.mode = "helm"`) | `charts/bootstrap`, `worca.tf` |

```
                router (Route from Worca's Ingress, edge TLS, the apps domain's wildcard certificate)
                    │
  project: oauth2-proxy ── controller ── worker pods (one per run / chat thread)
                               │
          ReadWriteMany claim (/worca, /projects) · SQLite on its own ReadWriteOnce claim
  Argo CD (GitOps operator) ── git (worca-cc chart)
  Secrets worca-auth, worca-secrets, worca-worker-credentials ◄── Vault Secrets Operator ── Vault / OpenBao
```

## What the cluster and the project must offer

- **A project** you are `admin` in (`oc new-project`, or ordered from your platform team), and a
  token for Terraform: best a service account of the project, so it outlives your login:

  ```bash
  oc -n <project> create sa terraform
  oc -n <project> create rolebinding terraform-admin --clusterrole=admin --serviceaccount=<project>:terraform
  export TF_VAR_token=$(oc -n <project> create token terraform --duration=720h)
  ```

  (Your own `oc whoami -t` works too, until it expires.)
- **The OpenShift GitOps operator** (`oc get csv | grep gitops`), for `argocd.mode = "operator"`.
  Without it, `argocd.mode = "helm"` installs Worca straight from a worca-cc checkout.
- **The Vault Secrets Operator** (`oc api-resources | grep secrets.hashicorp.com`). This root
  does not install it.
- **Room in the project's quota**: every pod has requests and limits (`resources`); Argo CD's set
  in `charts/argocd` is small. Shared clusters often grant far less CPU in requests than in
  limits, which is why the defaults request little.
- **Egress** to the model API, GitHub and your identity provider, directly or through
  `http_proxy`.

### Running as uid 1000

Worca's controller and worker image runs as uid 1000. OpenShift's default SCC, `restricted-v2`,
runs every pod under a uid from the project's range instead and refuses a fixed one. Either:

- **grant an SCC that allows any non-root uid** to Worca's two service accounts:
  `grant_scc = "nonroot-v2"`. Granting it takes the right to use that SCC, usually a cluster
  admin: apply once with such a token, or have the RoleBinding made for you; or
- **use a cluster whose default SCC already allows it** (some platforms run a variant of
  restricted-v2 with `runAsUser: MustRunAsNonRoot`): leave `grant_scc` empty.

Either way `fsGroup` stays the platform's (`pod_security.fs_group = null`): a fixed one outside the
project's range is refused too. oauth2-proxy takes whatever uid the platform gives it.

### Storage

SQLite needs a ReadWriteOnce claim (`storage.db_class`, empty = the cluster default; never NFS).
The shared volume needs ReadWriteMany:

| What the cluster has | Set |
|---|---|
| A ReadWriteMany storage class (ODF CephFS, NFS provisioner, ...) | `shared_class = "<class>"` |
| A claim made by someone else | `shared_existing_claim = "<name>"` |
| An NFS share bound through a statically provisioned PV (made by an admin or a self-service resource) | `shared_class = ""`, `shared_precreate = true`, and the self-service resource in `extra_manifests` |

On NFS the files belong to uid 1000. A share that grants write access by group needs that group in
`pod_security.supplemental_groups`; its top directory must be writable by it (the chart's root
`prepare` step is off: OpenShift refuses root containers).

## 1. Images

Worca's controller and worker images (`docker/Dockerfile` in worca-cc, targets `controller` and
`worker`; worker tags are `<worca_image_tag>-<engine>`) and oauth2-proxy
(`quay.io/oauth2-proxy/oauth2-proxy:v7.15.6`) in one registry (`registry`, `images`), with a pull
secret from `TF_VAR_registry_username`/`TF_VAR_registry_password`. To use the cluster's own
registry instead, push to the project's image streams
(`default-route-openshift-image-registry.apps.<cluster>/<project>/...`), set
`registry = "image-registry.openshift-image-registry.svc:5000"` with `<project>/...` repositories,
and leave the credentials empty: a project's pods may pull its own images.

Argo CD's images are the GitOps operator's.

## 2. Secrets in Vault

Three KV v2 entries, one per Kubernetes Secret; each entry's keys become that Secret's keys:

| Entry (`vault.*`, under `vault.kv_mount`) | Keys | Secret |
|---|---|---|
| `auth_path` (default `worca/auth`) | `client-secret` (the app registration's), `cookie-secret` | `worca-auth` (oauth2-proxy) |
| `controller_path` (default `worca/controller`) | `CLAUDE_CODE_OAUTH_TOKEN`, `GH_TOKEN`, ... any controller variable | `worca-secrets` |
| `worker_path` (default `worca/worker`) | `CLAUDE_CODE_OAUTH_TOKEN` (no GitHub tokens: workers run agents) | `worca-worker-credentials` |

```bash
vault kv put -mount=kv worca/auth \
  client-secret=- cookie-secret="$(openssl rand -base64 32 | tr -- '+/' '-_')" < client-secret.txt
vault kv put -mount=kv worca/controller CLAUDE_CODE_OAUTH_TOKEN=- < claude-token.txt
vault kv put -mount=kv worca/worker     CLAUDE_CODE_OAUTH_TOKEN=- < claude-token.txt
```

(`bao` for OpenBao takes the same arguments; add `-namespace=...` for a namespace.)

**How the operator logs in** (`vault.auth_method`):

- **`kubernetes`** (default): the `worca-vault` service account logs in; no secret in Terraform.
  Vault's kubernetes auth mount must know the cluster and verify tokens with an account that holds
  `system:auth-delegator`: `create_auth_delegator_binding = true` with cluster rights, or your
  platform's self-service resource for it in `extra_manifests`. After the first apply,
  `terraform output -raw vault_kubernetes_auth_commands` prints the Vault side (mount, config with
  the reviewer token this root creates, policy, role). Vault must reach the cluster's API.
- **`approle`**: `vault.role_id` and `TF_VAR_vault_approle_secret_id` (it lands in the state).
  Only the operator → Vault direction is needed.

`vault.address` empty uses the operator's default connection; set it (and `vault.ca_file` for a
private CA) for another server.

## 3. Configure and apply

```bash
cd openshift
cp terraform.tfvars.example terraform.tfvars   # fill in; it is gitignored
export TF_VAR_token=...                        # step "What the project must offer"
export TF_VAR_registry_username=... TF_VAR_registry_password=...
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Register `terraform output -raw oidc_redirect_uri` as a Web redirect URI of the OpenID Connect app
registration. `worca_host` under the cluster's apps domain needs no DNS or certificate: the router's
wildcard covers it. The route timeout annotation (`ingress_annotations`) keeps Worca's live
connections open past the router's 30 s default.

## 4. Check it

```bash
oc project <project>
oc get vaultstaticsecrets          # all three: no error, a secretMAC
oc get argocd,applications         # Argo CD Available; worca Synced/Healthy
oc get pods,pvc -w                 # controller, oauth2-proxy; a worker per chat
eval "$(terraform output -raw argocd_url_command)"
```

Open `terraform output -raw worca_url`, sign in and start a chat: a worker pod appears and goes
when it is idle. Argo CD signs in through OpenShift; `argocd.groups` may sign in, `argocd.admins`
administer.

## Platform-specific pieces

Everything a particular OpenShift platform does its own way is a variable:

| Platform difference | Variable |
|---|---|
| Default SCC allows any non-root uid, or not | `grant_scc` |
| fsGroup range, NFS group | `pod_security` |
| Storage self-service, statically provisioned NFS | `storage.shared_precreate`, `extra_manifests` |
| auth-delegator through a self-service resource | `extra_manifests` (or `create_auth_delegator_binding`) |
| Vault server, namespace, CA, login method | `vault` |
| Internal or internet-facing router | `ingress_class`, `worca_host` |
| Proxy for internet egress | `http_proxy`, `no_proxy` |
| Who may use Argo CD | `argocd.groups`, `argocd.admins` |
| Quota (requests vs limits) | `resources` |

## Tear down

```bash
terraform destroy
```

The Application goes first and Argo CD deletes Worca, then Argo CD, then the service accounts and
secrets. The claims Worca's chart made go with it; a precreated or existing shared claim (and the
NFS data behind it) is yours to keep or delete. The project, the images and the Vault entries stay.
