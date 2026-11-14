# Azure Container Registry for Worca's images

`<registry>.azurecr.io/<name>/worca` (controller) and `<name>/worca-worker` (workers), kept apart from
the deployment: a teardown leaves the images. [azure-aks/infra](../../azure-aks/infra) gives the
cluster's kubelet AcrPull on it. The Azure counterpart of [registry/ecr](../ecr).

- **Cost:** Basic tier, ~$5 a month with 10 GB included.
- **Untagged images** are not expired by Basic (retention policies are Premium). Remove them now and
  then: `az acr run --registry <registry> --cmd "acr purge --filter '.*:.*' --untagged --ago 1d" /dev/null`.

## Set up once

```bash
az login
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

## Push

```bash
REG=$(terraform output -raw registry)
az acr login --name "${REG%%.*}"
cd ../../../worca-cc
node tools/docker-build.mjs --tag "$REG/worca-poc/worca:poc"
node tools/docker-build.mjs --target worker --engine claude --tag "$REG/worca-poc/worca-worker:poc-claude"
docker push "$REG/worca-poc/worca:poc" && docker push "$REG/worca-poc/worca-worker:poc-claude"
```

Build on x86_64 with npm 10 (see [aws-eks/README.md](../../aws-eks/README.md), "Images").

## Remove

`terraform destroy` deletes the registry with its images.
