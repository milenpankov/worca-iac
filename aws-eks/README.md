# Worca on AWS EKS

Worca's Kubernetes deployment on EKS: a controller that starts a worker pod per run and chat
thread, sign-in through Microsoft Entra ID, secrets from SSM Parameter Store, and Argo CD deploying
Worca from its git branch.

```
                                     Entra ID (Worca's sign-in)
                                         ▲
 browser ──https──► ALB (ACM certificate, one for both hosts)
                     ├─ worca_host  ──► oauth2-proxy ──► worca controller ──(pods API)──► worker pods
                     │                                   │  SQLite on EBS gp3     (spot nodes, 0..N)
                     │                                   └──── EFS (shared /worca, /projects) ──┘
                     └─ argocd_host ──► Argo CD (own admin login) ── git: worca-cc deploy/helm/worca @ feat/worker-containers
 External Secrets ── SSM /worca/<env>/* ──► worca-auth, worca-secrets, worca-worker-credentials
```

Two Terraform roots, applied in order, each with its own state:

| Root | Providers | What it creates |
|---|---|---|
| [infra/](infra) | aws | VPC (public subnets, no NAT), EKS, an on-demand **system** node group (1 node), a spot **workers** node group (0..N, tainted), EBS and EFS CSI add-ons, EFS, ECR repositories, Pod Identity roles (the CSI drivers, the AWS Load Balancer Controller, Cluster Autoscaler, External Secrets reading only `/worca/<env>/*`) |
| [platform/](platform) | helm, kubernetes, aws | the AWS Load Balancer Controller, the ACM certificate, External Secrets, Cluster Autoscaler, Argo CD (on the ALB, its own `admin` login); then [charts/bootstrap](platform/charts/bootstrap): storage classes `gp3` and `efs-sc`, the SSM-backed ExternalSecrets, and the Argo CD Application that deploys Worca with [values/worca-poc.yaml](platform/values/worca-poc.yaml) |

**One ALB for everything.** Worca's and Argo CD's Ingresses share the IngressGroup `worca`, so
the AWS Load Balancer Controller builds one ALB with a rule per host. Further endpoints are more
Ingresses in that group (`alb_annotations` in `platform/addons.tf`), not more load balancers.

## Before you start

- **Tools:** Terraform 1.9 or newer, AWS CLI v2 signed in to the target account, kubectl, Helm,
  and Docker (to build the images).
- **Two host names** whose DNS you control: `worca_host` and `argocd_host`, e.g.
  `worca.example.com` and `argocd.worca.example.com`.
  - **With a Route 53 zone** (`route53_zone`, its name), Terraform validates the certificate and
    creates both records (aliases to the ALB) on every apply. For a domain whose DNS is
    elsewhere, delegate one subdomain to Route 53 once with [dns/route53](../dns/route53); it
    stays when this deployment is destroyed.
  - **Otherwise** you add the certificate's validation CNAMEs and two CNAMEs to the ALB yourself.
- **The Entra app registration** for Worca's sign-in is set in
  [values/worca-poc.yaml](platform/values/worca-poc.yaml) (`auth.oidc`: tenant and client id).
  Everyone in the tenant may sign in (`allowedGroups: []`).
  - **Redirect URI** (Web): add `https://<worca_host>/oauth2/callback`
    (`terraform output entra_redirect_uri`).
  - **Client secret:** goes to SSM only (step 3).
  - **Another app or tenant**, or only some app roles: edit `auth` in the values file. See
    worca-cc's `docs/auth.md`, "Microsoft Entra ID".

## Deploy

**1. Infrastructure** (~15–20 minutes, mostly EKS):

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # region, AZs, sizes
terraform init
terraform apply
$(terraform output -raw kubeconfig_command)    # kubectl now talks to the cluster
```

**2. Images.** Until worca-cc publishes worker images, build them from the branch and push them to
the ECR repositories (`terraform output ecr_repositories`):

```bash
REG=$(terraform -chdir=infra output -raw ecr_registry)
aws ecr get-login-password | docker login --username AWS --password-stdin "$REG"
cd ../worca-cc            # on feat/worker-containers
node tools/docker-build.mjs --tag "$REG/worca-poc/worca:poc"
node tools/docker-build.mjs --target worker --engine claude --tag "$REG/worca-poc/worca-worker:poc-claude"
docker push "$REG/worca-poc/worca:poc"
docker push "$REG/worca-poc/worca-worker:poc-claude"
```

The nodes are x86_64, so build on an x86_64 machine (or with `docker buildx --platform linux/amd64`).
`docker-build` packs the package with npm; npm 12 drops `npm-shrinkwrap.json` from the tarball and
the image build fails, so use npm 10 or 11.

**3. Secrets in SSM Parameter Store.** Create these as SecureStrings, so they never pass through
Terraform or its state. The platform root lists the exact names: `terraform output ssm_parameters`.

```bash
P=/worca/poc
aws ssm put-parameter --type SecureString --name $P/auth/client-secret --value '<Entra client secret>'
aws ssm put-parameter --type SecureString --name $P/auth/cookie-secret --value "$(openssl rand -base64 32 | tr -- '+/' '-_')"
aws ssm put-parameter --type SecureString --name $P/controller/CLAUDE_CODE_OAUTH_TOKEN --value '<token>'
aws ssm put-parameter --type SecureString --name $P/worker/CLAUDE_CODE_OAUTH_TOKEN --value '<token>'
```

`controller_env_secrets` and `worker_env_secrets` (platform tfvars) name which variables the two
Secrets carry; add `GH_TOKEN` to the controller's for pull requests. External Secrets re-reads SSM
every hour. To rotate sooner: `kubectl -n worca annotate externalsecret --all force-sync=$(date +%s) --overwrite`.

**4. Platform and Worca** (~5 minutes):

```bash
cd platform
cp terraform.tfvars.example terraform.tfvars   # hosts, mock_mode
terraform init
terraform apply
```

**Without** `route53_zone`, do the DNS once by hand:
1. Add the CNAMEs from `terraform output acm_validation_records`. ACM issues the certificate a
   few minutes later; until then the ALB has no HTTPS listener.
2. `terraform apply` again: the first apply may finish before the ALB exists.
3. CNAME both hosts to `terraform output load_balancer_hostname`.

**With** `route53_zone`, the certificate is validated during the first apply, and the second
`apply` creates the host records (the first may finish before the ALB exists).

Argo CD then syncs Worca. Watch it with:

```bash
kubectl -n argocd get applications
kubectl -n worca get pods,ingress,externalsecret
```

**5. Check it.**
- `https://<argocd_host>`: log in as `admin`. `terraform output -raw argocd_admin_password_command`
  prints the command that reads the password Argo CD generated in the cluster; Terraform never
  holds it. Change it (User Info → Update password), then delete the original:
  `kubectl -n argocd delete secret argocd-initial-admin-secret`. The `worca` application should
  be Synced and Healthy.
- `https://<worca_host>`: Entra sign-in, then Worca, which names you in the account corner.

With `mock_mode = true`, start a run. A worker pod waits (Pending), Cluster Autoscaler starts a
spot node (1–3 minutes), the run finishes, and about 5 minutes after the
last worker the node goes away:

```bash
kubectl -n worca get pods -l app.kubernetes.io/component=worker -w
kubectl get nodes -l worca.dev/pool=workers -w
```

Set `mock_mode = false` and apply for real runs.

## Day to day

- **New Worca commits:** Argo CD follows `worca_revision` (a branch) and syncs on its own, within
  about 3 minutes. Pin a tag or commit to stop following.
- **New images:** push the same tag again, then `kubectl -n worca rollout restart statefulset/worca`.
  Worker pods pull on start (`pullPolicy: Always`).
- **Values:** edit `platform/values/worca-poc.yaml`, then `terraform apply` in `platform/`.
- **Argo CD UI:** `https://<argocd_host>`, user `admin`.

## Remove everything

```bash
cd platform && terraform destroy   # Worca (Argo CD deletes its resources first), add-ons, the ALB
cd ../infra && terraform destroy   # cluster, nodes, EFS, ECR (images included)
```

Destroy `platform` first: the ALB and the volumes are made from inside the cluster, and the VPC
can't be deleted while they exist. The SSM parameters stay. Delete them with
`aws ssm delete-parameters --names $(aws ssm get-parameters-by-path --path /worca/poc --recursive --query 'Parameters[].Name' --output text)`.

## Cost (eu-central-1, on-demand list prices, approximate)

| Item | ~ per month |
|---|---|
| EKS control plane | $73 |
| System node, t3a.large, 24/7 | $60 |
| Worker spot nodes, ~2 h/day | $1–3 |
| ALB (base + a few LCUs + its public IPv4 addresses) | $20–25 |
| ACM certificate | $0 |
| EBS (2 node disks of 40 GB while running + 5 GB database) | $5–8 |
| EFS (a few GB) | $1–3 |
| Public IPv4 on nodes | $4–8 |
| ECR, SSM standard parameters, Pod Identity | ~$0 |
| **Total** | **≈ $165–180** |

Model tokens are extra and usually larger. The control plane is paid whether or not anything
runs, so `terraform destroy` the whole thing between demo periods.

## State

Both roots keep local state in their folder, and `platform` reads `../infra/terraform.tfstate`.
That's fine for one person. To share or automate, move both to an S3 backend: add
`backend "s3" { bucket = "...", key = "worca/poc/infra.tfstate", region = "...", use_lockfile = true }`
(Terraform 1.10+). Then switch `platform`'s `terraform_remote_state` to `backend = "s3"`.

## Known limits

- **One controller, one AZ.** SQLite sits on an EBS volume in the system node's AZ. Losing that
  node pauses runs until it's replaced; they resume afterwards.
- **Public subnets, no NAT.** Nodes have public IPs for outbound traffic, and their security group
  admits nothing from outside. The ALB reaches pods directly by IP, through security group rules
  the load balancer controller manages.
- **No NetworkPolicy:** the VPC CNI doesn't enforce it unless network policy is enabled on the
  add-on.
- **Argo CD is reachable from the internet** with only its `admin` password. Change the generated
  one, or restrict the ALB to known addresses: add
  `alb.ingress.kubernetes.io/inbound-cidrs` to Argo CD's Ingress annotations in `platform/addons.tf`.
- **The ALB's idle timeout** is one hour, so Worca's WebSockets survive quiet periods. It applies
  to the whole group.
