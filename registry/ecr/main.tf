# Worca's images, built from worca-cc and pushed from a workstation (aws-eks/README.md, "Images").
# Separate from the deployments, so a teardown keeps the images and a bring-up pulls them as they
# are. Nodes pull with their instance role (AmazonEC2ContainerRegistryReadOnly, any repository in
# the account). About $0.10 per GB-month.
data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "MUTABLE" # the PoC re-pushes `poc`; pin digests or versions beyond it
  force_delete         = true      # `terraform destroy` removes the images too

  image_scanning_configuration {
    scan_on_push = true
  }
}

# A re-pushed tag leaves the previous image untagged: gone after a day. Of the tagged ones, the
# newest keep_tagged_images stay.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Untagged images: one day"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the ${var.keep_tagged_images} most recent tagged images"
        selection    = { tagStatus = "tagged", tagPatternList = ["*"], countType = "imageCountMoreThan", countNumber = var.keep_tagged_images }
        action       = { type = "expire" }
      },
    ]
  })
}
