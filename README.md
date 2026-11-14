# worca-iac

Infrastructure as code for running [Worca](https://github.com/SinishaDjukic/worca-cc) with its
controller/worker topology (a controller, plus a container or pod per run and chat thread) and
sign-in through your own identity provider.

| Platform | Folder |
|---|---|
| AWS EKS | [aws-eks/](aws-eks) |
| AWS ECS (controller on EC2; workers on Fargate, Fargate Spot or spot EC2) | [aws-ecs/](aws-ecs) |
| Azure AKS | [azure-aks/](azure-aks) |
| Any Rancher-managed cluster, through the Rancher API (Argo CD, Vault Secrets Operator) | [rancher-api/](rancher-api) |
| An OpenShift project, with project rights only (OpenShift GitOps, Vault Secrets Operator) | [openshift/](openshift) |

Shared, long-lived pieces the deployments use:

| What | Folder |
|---|---|
| A subdomain delegated to Route 53 (the parent domain's DNS stays elsewhere) | [dns/route53/](dns/route53) |
| ECR repositories for Worca's images, kept across teardowns | [registry/ecr/](registry/ecr) |
| A subdomain delegated to Azure DNS | [dns/azure/](dns/azure) |
| Azure Container Registry for Worca's images, kept across teardowns | [registry/acr/](registry/acr) |
| Azure Key Vault for the deployment's secrets (the counterpart of SSM) | [secrets/azure-keyvault/](secrets/azure-keyvault) |

Each platform is self-contained: its own Terraform roots, values and README. Nothing is shared
between platforms until a second one shows what is really common.

## License

[MIT](LICENSE)
