output "registry" {
  description = "docker login to this, then push <registry>/<repository>:<tag>."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "repositories" {
  description = "Repository names; aws-eks/platform reads them by name (image_repositories)."
  value       = { for k, r in aws_ecr_repository.this : k => r.name }
}
