# The ReadWriteMany volume the controller and every worker pod share (/worca and /projects): EFS,
# dynamically provisioned through access points by the EFS CSI driver (platform: StorageClass efs-sc).
# The controller's SQLite database stays on EBS (gp3, ReadWriteOnce): SQLite on NFS corrupts.
resource "aws_efs_file_system" "shared" {
  creation_token   = "${var.name}-shared"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = { Name = "${var.name}-shared" }
}

resource "aws_security_group" "efs" {
  name_prefix = "${var.name}-efs-"
  description = "NFS from the EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "NFS from nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_efs_mount_target" "shared" {
  for_each = { for i, s in module.vpc.public_subnets : i => s }

  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}
