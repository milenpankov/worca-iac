output "worca_url" {
  value = "https://${var.worca_host}"
}

output "entra_redirect_uri" {
  description = "Register this as a Web redirect URI of Worca's Entra app registration."
  value       = "https://${var.worca_host}/oauth2/callback"
}

output "load_balancer_hostname" {
  description = "The ALB. CNAME worca_host to it unless route53_zone is set."
  value       = aws_lb.this.dns_name
}

output "acm_validation_records" {
  description = "Without route53_zone: add these CNAMEs at your DNS provider; the apply waits for them."
  value = var.route53_zone != "" ? [] : [
    for o in aws_acm_certificate.this.domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ]
}

output "cluster" {
  value = aws_ecs_cluster.this.name
}

output "ssm_parameters" {
  description = "The parameters to create before Worca can start (README: Secrets)."
  value = sort(concat(
    ["${local.ssm_prefix}/auth/tenant-id", "${local.ssm_prefix}/auth/client-id", "${local.ssm_prefix}/auth/client-secret", "${local.ssm_prefix}/auth/cookie-secret"],
    [for k in var.controller_env_secrets : "${local.ssm_prefix}/controller/${k}"],
    [for k in var.worker_env_secrets : "${local.ssm_prefix}/worker/${k}"],
  ))
}

output "system_instance_id" {
  description = "For a shell: aws ssm start-session --target <id>."
  value       = aws_instance.system.id
}

output "watch_commands" {
  description = "Worker tasks and instances, refreshed every 2 seconds."
  value       = <<-EOT
    watch -n 2 'aws ecs list-tasks --cluster ${aws_ecs_cluster.this.name} --started-by worca-${var.name} --query "length(taskArns)"; aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.workers.name} --query "AutoScalingGroups[0].Instances[].[InstanceId,InstanceType,LifecycleState]" --output text'
  EOT
}
