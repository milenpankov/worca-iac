# Images built from worca-cc's feat/worker-containers (README: "Images"). Nodes pull with their
# instance role (the EKS module attaches AmazonEC2ContainerRegistryReadOnly).
locals {
  repositories = ["worca", "worca-worker"]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.repositories)

  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "MUTABLE" # the PoC re-pushes `poc`; pin digests or versions beyond it
  force_delete         = true      # `terraform destroy` removes the images too

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}
