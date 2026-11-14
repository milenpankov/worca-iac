# The volume the controller and every worker share, /worca and /projects: EFS, one access point
# each, owned by uid 1000 (the images' user). The controller's SQLite database is NOT here (SQLite
# on NFS corrupts): it is on its own EBS volume on the system instance (compute.tf).
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
  description = "NFS from the ECS instances"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.system.id, aws_security_group.workers.id, aws_security_group.worker_tasks.id]
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

resource "aws_efs_access_point" "shared" {
  for_each = toset(["worca", "projects"])

  file_system_id = aws_efs_file_system.shared.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/${each.key}"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0775"
    }
  }

  tags = { Name = "${var.name}-${each.key}" }
}
