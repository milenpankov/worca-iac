locals {
  tags = merge({
    Project     = "worca"
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# Public subnets only: no NAT gateway (~$32/month per AZ). Nodes get public IPs for egress; their
# security group admits nothing from the internet (the NLB reaches Traefik's node ports).
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.vpc_cidr
  azs  = var.availability_zones

  public_subnets          = [for i, _ in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i)]
  map_public_ip_on_launch = true

  enable_nat_gateway = false
  enable_vpn_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
}
