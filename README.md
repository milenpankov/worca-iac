# worca-iac

Infrastructure as code for running [Worca](https://github.com/SinishaDjukic/worca-cc) with its
controller/worker topology (a controller, plus a container or pod per run and chat thread) and
sign-in through your own identity provider.

| Platform | Folder |
|---|---|
| AWS EKS | [aws-eks/](aws-eks) |
| AWS ECS (controller on EC2; workers on Fargate, Fargate Spot or spot EC2) | [aws-ecs/](aws-ecs) |

Shared, long-lived pieces the deployments use:

| What | Folder |
|---|---|
| A subdomain delegated to Route 53 (the parent domain's DNS stays elsewhere) | [dns/route53/](dns/route53) |
| ECR repositories for Worca's images, kept across teardowns | [registry/ecr/](registry/ecr) |

Each platform is self-contained: its own Terraform roots, values and README. Nothing is shared
between platforms until a second one shows what is really common.

## License

[MIT](LICENSE)
