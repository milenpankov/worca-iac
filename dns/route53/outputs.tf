output "zone_name" {
  description = "Use as route53_zone in aws-eks/platform."
  value       = aws_route53_zone.this.name
}

output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Add these as NS records for zone_name at the parent domain's DNS provider."
  value       = aws_route53_zone.this.name_servers
}

output "delegation" {
  description = "The NS records the parent domain needs, one per line."
  value       = join("\n", [for ns in aws_route53_zone.this.name_servers : "${var.zone_name}  NS  ${ns}."])
}
