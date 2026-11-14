# The ECS cluster and the EC2 capacity it runs on:
#   system    one on-demand instance (not in an Auto Scaling group) at a fixed private address, with
#             the database's EBS volume: the controller service runs only here.
#   workers   a spot Auto Scaling group, 0..worker_max_instances, behind a capacity provider with
#             managed scaling: a worker task that finds no room waits in PROVISIONING while ECS starts
#             an instance (2-4 minutes from zero); an empty instance is removed again.

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled" # CloudWatch metrics per task cost extra; not needed for the PoC
  }
}

# The current ECS-optimized Amazon Linux 2023 AMI (x86_64, like the images).
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# --- The instances' own role: the ECS agent, image pulls, and Session Manager for a shell ---

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name_prefix        = "${var.name}-instance-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.name}-instance-"
  role        = aws_iam_role.instance.name
}

# --- System instance ---

resource "aws_ebs_volume" "db" {
  availability_zone = var.availability_zones[0]
  size              = var.db_volume_size
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${var.name}-db" }
}

resource "aws_instance" "system" {
  ami                    = data.aws_ssm_parameter.ecs_ami.insecure_value
  instance_type          = var.system_instance_type
  subnet_id              = module.vpc.public_subnets[0]
  private_ip             = local.controller_ip
  vpc_security_group_ids = [aws_security_group.system.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/templates/system-user-data.sh", {
    cluster   = aws_ecs_cluster.this.name
    volume_id = aws_ebs_volume.db.id
  })
  user_data_replace_on_change = true

  # IMDSv2 only, one hop: no container reaches the instance's credentials through a bridge network.
  # Containers on the host network (the controller's task) are blocked by uid in the user data.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = { Name = "${var.name}-system" }

  lifecycle {
    # A newer AMI is picked up on replacement (taint), not on every apply.
    ignore_changes = [ami]
  }
}

resource "aws_volume_attachment" "db" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.db.id
  instance_id = aws_instance.system.id
  # Unmounted cleanly by the instance's shutdown when it is replaced or destroyed.
  stop_instance_before_detaching = true
}

# --- Worker instances ---

resource "aws_launch_template" "workers" {
  name_prefix   = "${var.name}-workers-"
  image_id      = data.aws_ssm_parameter.ecs_ami.insecure_value
  instance_type = var.worker_instance_types[0]

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.workers.id]
  }

  user_data = base64encode(templatefile("${path.module}/templates/worker-user-data.sh", {
    cluster = aws_ecs_cluster.this.name
  }))

  # Worker containers (bridge network) are one hop further: the hop limit keeps IMDSv2 tokens, and
  # so the instance's role, out of their reach.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 30
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name}-worker" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${var.name}-worker" })
  }
}

resource "aws_autoscaling_group" "workers" {
  name_prefix         = "${var.name}-workers-"
  min_size            = 0
  max_size            = var.worker_max_instances
  vpc_zone_identifier = module.vpc.public_subnets

  # Managed termination protection: ECS lifts it only on instances with no worker task, so scaling
  # in never ends a running worker.
  protect_from_scale_in = true
  # On destroy, instances are terminated with the group even while protected.
  force_delete = true

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"
    }
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.workers.id
        version            = "$Latest"
      }
      dynamic "override" {
        for_each = var.worker_instance_types
        content {
          instance_type = override.value
        }
      }
    }
  }

  # Managed scaling sets desired_capacity.
  lifecycle {
    ignore_changes = [desired_capacity]
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "workers" {
  name = "${var.name}-workers"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.workers.arn
    managed_termination_protection = "ENABLED"
    managed_draining               = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      # From zero ECS cannot tell how much one task needs and starts the largest step: keep it to one
      # instance (several workers starting at once then scale one instance at a time).
      maximum_scaling_step_size = 1
      instance_warmup_period    = 60
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name
  # All three are always available: worker_launch picks the one Worca's workers use.
  capacity_providers = [aws_ecs_capacity_provider.workers.name, "FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.workers.name
    weight            = 1
  }
}
