data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  ssm_prefix = "/worca/${var.environment}"

  # Worker nodes: what the Worca chart's worker.nodeSelector / tolerations name (platform/values).
  worker_label = { "worca.dev/pool" = "workers" }
  worker_taint = { key = "worca.dev/worker", value = "true", effect = "NO_SCHEDULE" }
  system_label = { "worca.dev/pool" = "system" }

  node_disk = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 40 # worker images are ~2 GB per engine, plus checkouts in /tmp
        volume_type           = "gp3"
        encrypted             = true
        delete_on_termination = true
      }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  # kubectl, helm and terraform reach the API from outside (no VPN in the PoC).
  endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for i, arn in var.cluster_admin_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Control-plane logs cost CloudWatch money; the PoC keeps none.
  enabled_log_types           = []
  create_cloudwatch_log_group = false

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
    aws-efs-csi-driver = {
      pod_identity_association = [{
        role_arn        = module.efs_csi_pod_identity.iam_role_arn
        service_account = "efs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    # Always on, one node, in the first AZ: the controller's ReadWriteOnce EBS volume lives there.
    system = {
      ami_type              = "AL2023_x86_64_STANDARD"
      instance_types        = var.system_instance_types
      capacity_type         = "ON_DEMAND"
      subnet_ids            = [module.vpc.public_subnets[0]]
      min_size              = 1
      max_size              = 1
      desired_size          = 1
      labels                = local.system_label
      block_device_mappings = local.node_disk
    }

    # Worker pods only (taint); spot; 0 nodes until a run needs one. Cluster Autoscaler scales it.
    workers = {
      ami_type              = "AL2023_x86_64_STANDARD"
      instance_types        = var.worker_instance_types
      capacity_type         = "SPOT"
      subnet_ids            = module.vpc.public_subnets
      min_size              = 0
      max_size              = var.worker_max_nodes
      desired_size          = 0
      labels                = local.worker_label
      taints                = { worker = local.worker_taint }
      block_device_mappings = local.node_disk
    }
  }
}

# Scale from zero: with no node running, Cluster Autoscaler learns a group's labels and taints from
# these ASG tags (EKS does not copy them onto the managed node group's ASG).
locals {
  worker_asg_tags = merge(
    { for k, v in local.worker_label : "k8s.io/cluster-autoscaler/node-template/label/${k}" => v },
    { "k8s.io/cluster-autoscaler/node-template/taint/${local.worker_taint.key}" = "${local.worker_taint.value}:NoSchedule" },
  )
}

resource "aws_autoscaling_group_tag" "workers" {
  for_each = local.worker_asg_tags

  autoscaling_group_name = module.eks.eks_managed_node_groups["workers"].node_group_autoscaling_group_names[0]

  tag {
    key                 = each.key
    value               = each.value
    propagate_at_launch = false
  }
}
