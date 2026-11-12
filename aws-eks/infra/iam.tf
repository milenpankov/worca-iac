# EKS Pod Identity roles. The CSI drivers' associations are made by their add-ons (eks.tf); the
# others here, for the service accounts the platform root installs.

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                      = "${var.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
}

module "efs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                      = "${var.name}-efs-csi"
  attach_aws_efs_csi_policy = true
}

module "cluster_autoscaler_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                             = "${var.name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
    }
  }
}

# The AWS Load Balancer Controller: one ALB for every Ingress in the `worca` IngressGroup.
module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                            = "${var.name}-aws-lb-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

# External Secrets reads /worca/<environment>/* from SSM Parameter Store, nothing else. Parameters
# are SecureStrings you create yourself (README: "Secrets"), so their values never enter
# Terraform state.
module "external_secrets_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                           = "${var.name}-external-secrets"
  attach_external_secrets_policy = true
  external_secrets_ssm_parameter_arns = [
    "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*",
  ]
  # SecureStrings are decrypted with this account's keys in this region (aws/ssm by default).
  external_secrets_kms_key_arns = [
    "arn:${data.aws_partition.current.partition}:kms:${var.region}:${data.aws_caller_identity.current.account_id}:key/*",
  ]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}
