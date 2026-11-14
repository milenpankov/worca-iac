# ECR repositories for Worca's images

`<name>/worca` (controller) and `<name>/worca-worker` (workers), kept apart from the deployments:
a teardown leaves the images, and the next bring-up pulls them without building again.
[aws-eks/platform](../../aws-eks/platform) finds the repositories by name (`image_repositories`).

- **Lifecycle:** an image left untagged by a re-push expires after a day; of the tagged ones the
  newest `keep_tagged_images` (10) stay.
- **Cost:** $0.10 per GB-month. The controller and the Claude worker image are about 0.8 GB
  compressed. Pushing and pulling within the region cost nothing.

## Set up once

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

Building and pushing the images: [aws-eks/README.md](../../aws-eks/README.md), "Images".

## Remove

`terraform destroy` deletes the repositories with their images (`force_delete`). They are tagged
`Project = <name>` (default `worca-poc`).
