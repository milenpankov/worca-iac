# Worca on Amazon ECS

Worca on ECS with sign-in through Microsoft Entra ID and secrets from SSM Parameter Store, as one
Terraform root:
- **Controller:** one EC2 instance.
- **Workers:** one ECS task per run and per chat thread, started by Worca's `ecs` executor
  (worca-cc `docs/ecs.md`), on Fargate or on spot instances.

```
 browser ──https──► ALB (ACM) ──► oauth2-proxy ─┐   system instance (on-demand, fixed private IP)
                                                └─► worca controller ── SQLite on its own EBS volume
                                                        │ RunTask / StopTask
                                                        ▼
                     worker tasks: Fargate | Fargate Spot | spot instances 0..N (worker_launch)
                                │ ws://<controller IP>:4319
                     EFS (/worca, /projects) shared by the controller and every worker
 SSM /worca/<env>/* ──► the task definitions' secrets (no secret in Terraform state)
```

## Where workers run: `worker_launch`

| Value | A worker's start | Cost | Notes |
|---|---|---|---|
| `fargate` (default) | ~30–90 s, every time (the image is pulled each time) | ~$0.05 per worker-hour (1 vCPU, 4 GB) | no instances |
| `fargate-spot` | the same | ~70% less | AWS may reclaim a task at two minutes' notice: its run pauses and resumes |
| `ec2` | ~3 min when no worker instance is up (ECS's managed scaling reacts after 1–2 min), then seconds | spot instance ~$0.03/h while up, shared by 2 workers | the instance is removed some 15 min after its last worker |

Change it in `terraform.tfvars`, then run `terraform apply`. Workers already running finish where they are,
and new ones start in the new place. All three kinds of capacity stay defined in the cluster, and the
empty Auto Scaling group costs nothing.

- **Network:** Fargate tasks get their own network interface with a public IP, because there's no NAT.
  Their security group admits nothing from outside. On EC2, worker containers use bridge networking on
  the instance.
- **Storage:** both kinds mount the shared EFS through access points owned by uid 1000.

## Before you start

- **Tools:** Terraform 1.9 or newer, AWS CLI v2, and Docker to build the images.
- **Images** in the [registry/ecr](../registry/ecr) repositories, built from worca-cc with the `ecs`
  executor:
  - the controller `worca-poc/worca:<controller_image_tag>`;
  - one worker per engine, `worca-poc/worca-worker:<tag>` (`worker_engines`).

  See [aws-eks/README.md](../aws-eks/README.md), step 2, for the build commands. Build for x86_64 with npm 10.
- **DNS:** with `route53_zone` set (a Route 53 public zone, e.g. from [dns/route53](../dns/route53)),
  Terraform validates the certificate and creates the record. Without it, add the records from the outputs
  yourself.
- **Entra app registration:** add the Web redirect URI `https://<worca_host>/oauth2/callback`
  (`terraform output entra_redirect_uri`).
- **SSM parameters** under `/worca/<environment>/`, the same ones the EKS deployment uses (`terraform output
  ssm_parameters`):

  ```bash
  P=/worca/poc
  aws ssm put-parameter --type String --name $P/auth/tenant-id --value '<Directory (tenant) ID>'
  aws ssm put-parameter --type String --name $P/auth/client-id --value '<Application (client) ID>'
  aws ssm put-parameter --type SecureString --name $P/auth/client-secret --value '<Entra client secret>'
  aws ssm put-parameter --type SecureString --name $P/auth/cookie-secret --value "$(openssl rand -base64 32 | tr -- '+/' '-_')"
  aws ssm put-parameter --type SecureString --name $P/controller/CLAUDE_CODE_OAUTH_TOKEN --value '<token>'
  aws ssm put-parameter --type SecureString --name $P/worker/CLAUDE_CODE_OAUTH_TOKEN --value '<token>'
  ```

## Deploy (~10 minutes)

```bash
cp terraform.tfvars.example terraform.tfvars   # host, zone, image tags, worker_launch
terraform init
terraform apply
```

Then open `terraform output -raw worca_url`, sign in, and start a chat. To watch the workers:

```bash
aws ecs list-tasks --cluster worca-ecs --started-by worca-worca-ecs   # this Worca's worker tasks
aws logs tail /ecs/worca-ecs --follow                                 # controller, oauth2-proxy and workers
```

- **New images:** push the same tag, then run
  `aws ecs update-service --cluster worca-ecs --service controller --force-new-deployment`.
  Worker tasks pull on every start.
- **A shell on the controller's instance:** `aws ssm start-session --target $(terraform output -raw system_instance_id)`.

## How it is built

- **Controller service:** runs only on the system instance, in host network mode.
  - oauth2-proxy listens on 4180 for the ALB, and Worca listens on 4319 for the workers. The instance's
    security group admits only these two ports.
  - Host mode gives Worca the instance's public IP for outbound traffic. On EC2, an `awsvpc` task gets no
    public IP, and there is no NAT.
  - The instance's fixed private IP (`.10` of the first subnet) is the address workers dial.
- **Database:** SQLite lives on its own gp3 volume, mounted at `/var/lib/worca-db`. It is formatted once and
  survives instance replacement. Shared files are on EFS; SQLite never goes on NFS.
- **Sign-in:**
  - oauth2-proxy reads its config from a file. A short-lived `auth-config` container writes it into the
    task's own volume, together with the client secret from SSM.
  - Worca checks the ID token itself against Entra's keys.
- **AWS permissions:**
  - Only the controller has a task role: it may run, tag, describe, list and stop this cluster's worker
    tasks, and pass the workers' execution role.
  - Workers get no AWS credentials.
  - The instances use IMDSv2 with a hop limit of 1. On the system instance, only root may reach the
    metadata service, because the controller shares the host network.
- **Spot workers (`ec2`):** an Auto Scaling group of 0..`worker_max_instances` behind an ECS capacity
  provider with managed scaling and managed termination protection, so scaling in never ends a running
  worker.

## Tear down

```bash
terraform destroy
```

Before the service and the cluster are deleted, a destroy step stops any worker tasks Worca started, using
the AWS CLI. What stays: the images, the DNS zone and the SSM parameters.

## Cost (eu-central-1, approximate, per month)

| Item | ~ |
|---|---|
| System instance t3a.large, on-demand 24/7 | $60 |
| ALB (base + LCUs + its public IPv4 addresses) | $20–25 |
| Public IPv4: the system instance, plus each worker while it runs | $4 + cents |
| EBS (root 30 GB + database 10 GB) | $4 |
| EFS (a few GB) | $1–3 |
| Workers, ~2 h/day (Fargate · Fargate Spot · EC2 spot) | ~$3 · ~$1 · ~$2 |
| CloudWatch Logs (7 days) | < $1 |
| **Total** | **≈ $90–100** |

There is no control-plane fee: ECS itself costs nothing, unlike EKS's $73.
