# Read by the platform root (terraform_remote_state). Nothing secret here.

output "region" {
  value = var.region
}

output "environment" {
  value = var.environment
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "efs_file_system_id" {
  value = aws_efs_file_system.shared.id
}

output "ssm_prefix" {
  description = "Where the platform's External Secrets reads parameters from."
  value       = local.ssm_prefix
}

output "ecr_registry" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "node_pools" {
  description = "Labels and taints the Worca values pin pods with."
  value = {
    system_label = local.system_label
    worker_label = local.worker_label
    worker_taint = { key = local.worker_taint.key, value = local.worker_taint.value, effect = "NoSchedule" }
  }
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
