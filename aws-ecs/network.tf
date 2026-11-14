locals {
  tags = merge({
    Project     = "worca"
    Environment = var.environment
    Deployment  = var.name
    ManagedBy   = "terraform"
  }, var.tags)

  # The system instance's fixed address: workers dial the controller here (WORCA_CONTROLLER_URL),
  # and it stays the same when the instance is replaced.
  controller_ip = cidrhost(module.vpc.public_subnets_cidr_blocks[0], 10)
}

# Public subnets only: no NAT gateway (~$32/month per AZ). Instances get public IPs for outbound
# traffic; their security groups admit nothing from the internet.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.vpc_cidr
  azs  = var.availability_zones

  public_subnets          = [for i, _ in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i)]
  map_public_ip_on_launch = true

  enable_nat_gateway   = false
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "HTTPS from anywhere to the ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "redirected to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The system instance (the controller's task uses its network: host mode). oauth2-proxy from the
# ALB, Worca's worker listener from worker instances; Worca's own port 4317 from nothing.
resource "aws_security_group" "system" {
  name_prefix = "${var.name}-system-"
  description = "Worca controller instance"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "oauth2-proxy from the ALB"
    from_port       = 4180
    to_port         = 4180
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    description     = "the worker listener from worker instances"
    from_port       = 4319
    to_port         = 4319
    protocol        = "tcp"
    security_groups = [aws_security_group.workers.id, aws_security_group.worker_tasks.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Worker instances: worker containers (bridge network) only dial out, to the controller and the internet.
resource "aws_security_group" "workers" {
  name_prefix = "${var.name}-workers-"
  description = "Worca worker instances: no inbound"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Worker tasks on Fargate (awsvpc: each task has its own network interface and this group). Like
# the instances: no inbound, out to the controller and the internet.
resource "aws_security_group" "worker_tasks" {
  name_prefix = "${var.name}-worker-tasks-"
  description = "Worca worker tasks on Fargate: no inbound"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
