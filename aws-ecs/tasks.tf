# What runs: the controller service (Worca + oauth2-proxy, on the system instance) and one worker
# task definition per engine, which the controller starts with RunTask (Worca's ecs executor).

data "aws_ecr_repository" "images" {
  for_each = var.image_repositories
  name     = each.value
}

# The Entra app registration's tenant and client id: String parameters you create (README).
data "aws_ssm_parameter" "entra" {
  for_each = toset(["tenant-id", "client-id"])
  name     = "${local.ssm_prefix}/auth/${each.key}"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

locals {
  controller_image = "${data.aws_ecr_repository.images["controller"].repository_url}:${var.controller_image_tag}"
  worker_image     = data.aws_ecr_repository.images["worker"].repository_url
  tenant_id        = data.aws_ssm_parameter.entra["tenant-id"].insecure_value
  client_id        = data.aws_ssm_parameter.entra["client-id"].insecure_value
  issuer_url       = "https://login.microsoftonline.com/${local.tenant_id}/v2.0"
  jwks_url         = "https://login.microsoftonline.com/${local.tenant_id}/discovery/v2.0/keys"
  worker_port      = 4319
  fargate          = var.worker_launch != "ec2"

  log = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.this.name
      awslogs-region        = var.region
      awslogs-stream-prefix = "worca"
    }
  }

  env = { for k, v in merge({
    # Where Worca keeps its data: the database on the system instance's EBS volume, the rest on EFS.
    WORCA_DB_DIR           = "/worca-db"
    WORCA_HOME             = "/worca"
    WORCA_PROJECTS_ROOT    = "/projects"
    WORCA_HOST             = "0.0.0.0" # the instance's security group admits only 4180 (oauth2-proxy) and 4319 (workers)
    PORT                   = "4317"
    TZ                     = var.timezone
    WORCA_INSTANCE_ID      = var.name
    WORCA_ALLOWED_HOSTS    = var.worca_host
    WORCA_DRAIN_TIMEOUT_MS = "20000"

    # Workers: an ECS task each, where worker_launch says; they dial this address.
    WORCA_EXECUTOR               = "ecs"
    WORCA_WORKER_PORT            = tostring(local.worker_port)
    WORCA_CONTROLLER_URL         = "ws://${local.controller_ip}:${local.worker_port}"
    WORCA_ECS_CLUSTER            = aws_ecs_cluster.this.name
    WORCA_ECS_REGION             = var.region
    WORCA_ECS_TASK_DEFINITION    = "${var.name}-worker-{engine}"
    WORCA_ECS_CAPACITY_PROVIDER  = local.fargate ? (var.worker_launch == "fargate-spot" ? "FARGATE_SPOT" : "FARGATE") : aws_ecs_capacity_provider.workers.name
    WORCA_ECS_PENDING_TIMEOUT_MS = "600000" # an instance from zero: 2-4 minutes
    WORCA_WORKER_START_OUTER_MS  = "900000"
    WORCA_WORKER_MAX             = tostring(var.max_workers)
    WORCA_WORKER_CHAT_IDLE_MS    = "600000"

    # Sign-in: oauth2-proxy passes the session's ID token, which Worca checks against Entra's keys.
    WORCA_IDENTITY_ISSUER      = local.issuer_url
    WORCA_IDENTITY_JWKS_URL    = local.jwks_url
    WORCA_IDENTITY_AUDIENCE    = local.client_id
    WORCA_IDENTITY_EMAIL_CLAIM = "preferred_username"
    WORCA_IDENTITY_TEAMS_CLAIM = "roles"
    }, var.mock_mode ? { WORCA_MOCK = "1" } : {},
    # Fargate tasks have their own network interface: a public address to pull and reach the
    # internet (no NAT), and the worker_tasks security group.
    local.fargate ? {
      WORCA_ECS_SUBNETS          = join(",", module.vpc.public_subnets)
      WORCA_ECS_SECURITY_GROUPS  = aws_security_group.worker_tasks.id
      WORCA_ECS_ASSIGN_PUBLIC_IP = "ENABLED"
  } : {}) : k => v }

  # oauth2-proxy's configuration (the chart's auth.yaml, the Compose overlay's oauth2-proxy.yaml):
  # written to a file by the auth-config container, since oauth2-proxy reads it from a file only.
  oauth2_proxy_config = yamlencode({
    server = { bindAddress = "0.0.0.0:4180" }
    upstreamConfig = {
      upstreams = [{ id = "worca", path = "/", uri = "http://127.0.0.1:4317", passHostHeader = true, proxyWebSockets = true }]
    }
    injectRequestHeaders = [{ name = "X-Worca-Identity", values = [{ claimSource = { claim = "id_token" } }] }]
    providers = [{
      id                    = "oidc"
      provider              = "oidc"
      name                  = "Worca"
      clientID              = local.client_id
      clientSecretFile      = "/etc/oauth2-proxy/client-secret"
      scope                 = "openid email profile offline_access"
      code_challenge_method = "S256"
      allowedGroups         = var.allowed_groups
      oidcConfig = {
        issuerURL         = local.issuer_url
        jwksURL           = local.jwks_url
        emailClaim        = "preferred_username"
        groupsClaim       = "roles"
        audienceClaims    = ["aud"]
        insecureSkipNonce = false
      }
    }]
  })

  shared_volumes = [for ap in ["worca", "projects"] : {
    name = "shared-${ap}"
    efs = {
      file_system_id  = aws_efs_file_system.shared.id
      access_point_id = aws_efs_access_point.shared[ap].id
    }
  }]
  shared_mounts = [
    { sourceVolume = "shared-worca", containerPath = "/worca", readOnly = false },
    { sourceVolume = "shared-projects", containerPath = "/projects", readOnly = false },
  ]
}

# --- Controller ---

resource "aws_ecs_task_definition" "controller" {
  family                   = "${var.name}-controller"
  requires_compatibilities = ["EC2"]
  network_mode             = "host" # the instance's public address for outbound traffic, its fixed private one for workers
  execution_role_arn       = aws_iam_role.controller_execution.arn
  task_role_arn            = aws_iam_role.controller.arn

  volume {
    name      = "db"
    host_path = "/var/lib/worca-db"
  }
  volume {
    name = "auth-config"
    docker_volume_configuration {
      scope  = "task"
      driver = "local"
    }
  }
  dynamic "volume" {
    for_each = local.shared_volumes
    content {
      name = volume.value.name
      efs_volume_configuration {
        file_system_id     = volume.value.efs.file_system_id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = volume.value.efs.access_point_id
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([
    {
      # Writes oauth2-proxy's configuration and client secret into the task's own volume, then ends.
      name              = "auth-config"
      image             = local.controller_image
      essential         = false
      user              = "0"
      entryPoint        = ["/bin/sh", "-ec"]
      command           = ["umask 022; printf '%s' \"$CONFIG\" > /config/oauth2-proxy.yaml; printf '%s' \"$CLIENT_SECRET\" > /config/client-secret; chmod 0444 /config/*"]
      environment       = [{ name = "CONFIG", value = local.oauth2_proxy_config }]
      secrets           = [{ name = "CLIENT_SECRET", valueFrom = "${local.ssm_arn}/auth/client-secret" }]
      mountPoints       = [{ sourceVolume = "auth-config", containerPath = "/config" }]
      memoryReservation = 32
      logConfiguration  = local.log
    },
    {
      name         = "oauth2-proxy"
      image        = var.oauth2_proxy_image
      essential    = true
      command      = ["--alpha-config=/etc/oauth2-proxy/oauth2-proxy.yaml"]
      dependsOn    = [{ containerName = "auth-config", condition = "SUCCESS" }]
      portMappings = [{ containerPort = 4180, hostPort = 4180, protocol = "tcp" }]
      environment = [for k, v in {
        OAUTH2_PROXY_REDIRECT_URL         = "https://${var.worca_host}/oauth2/callback"
        OAUTH2_PROXY_EMAIL_DOMAINS        = "*"
        OAUTH2_PROXY_REVERSE_PROXY        = "true"
        OAUTH2_PROXY_SKIP_PROVIDER_BUTTON = "true"
        OAUTH2_PROXY_COOKIE_NAME          = "_worca_auth"
        OAUTH2_PROXY_COOKIE_SECURE        = "true"
        OAUTH2_PROXY_COOKIE_EXPIRE        = "12h"
        OAUTH2_PROXY_COOKIE_REFRESH       = "4m"
        OAUTH2_PROXY_SILENCE_PING_LOGGING = "true"
      } : { name = k, value = v }]
      secrets           = [{ name = "OAUTH2_PROXY_COOKIE_SECRET", valueFrom = "${local.ssm_arn}/auth/cookie-secret" }]
      mountPoints       = [{ sourceVolume = "auth-config", containerPath = "/etc/oauth2-proxy", readOnly = true }]
      memoryReservation = 64
      memory            = 256
      logConfiguration  = local.log
    },
    {
      name         = "worca"
      image        = local.controller_image
      essential    = true
      command      = ["worca", "ui"]
      portMappings = [{ containerPort = local.worker_port, hostPort = local.worker_port, protocol = "tcp" }]
      environment  = [for k, v in local.env : { name = k, value = v }]
      secrets      = [for k in var.controller_env_secrets : { name = k, valueFrom = "${local.ssm_arn}/controller/${k}" }]
      mountPoints  = concat([{ sourceVolume = "db", containerPath = "/worca-db", readOnly = false }], local.shared_mounts)
      healthCheck = {
        command     = ["CMD", "curl", "-fsS", "--max-time", "4", "-H", "Host: localhost", "http://127.0.0.1:4317/api/health"]
        interval    = 15
        timeout     = 5
        retries     = 4
        startPeriod = 120
      }
      # The drain (20 s) plus the rest of the shutdown, before SIGKILL.
      stopTimeout       = 90
      memoryReservation = 1024
      memory            = 4096
      logConfiguration  = local.log
    },
  ])
}

# Stops the worker tasks the controller started (Terraform does not know them) before the service
# and the cluster go, so destroy is not refused over tasks still running. Needs the AWS CLI.
resource "terraform_data" "stop_workers" {
  input = { cluster = aws_ecs_cluster.this.name, region = var.region, started_by = "worca-${var.name}" }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      for t in $(aws ecs list-tasks --region ${self.input.region} --cluster ${self.input.cluster} --started-by ${self.input.started_by} --query 'taskArns[]' --output text); do
        aws ecs stop-task --region ${self.input.region} --cluster ${self.input.cluster} --task "$t" --reason 'terraform destroy' >/dev/null
      done
    EOT
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

resource "aws_ecs_service" "controller" {
  name            = "controller"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.controller.arn
  desired_count   = 1
  launch_type     = "EC2"

  # One owner of the database at a time: the old task stops before the new one starts.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 180

  placement_constraints {
    type       = "memberOf"
    expression = "ec2InstanceId == ${aws_instance.system.id}"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.worca.arn
    container_name   = "oauth2-proxy"
    container_port   = 4180
  }

  depends_on = [aws_lb_listener.https, aws_volume_attachment.db, terraform_data.stop_workers, aws_efs_mount_target.shared]
}

# --- Workers ---

resource "aws_ecs_task_definition" "worker" {
  for_each = var.worker_engines

  family = "${var.name}-worker-${each.key}"
  # EC2: bridge network, no ENI per task (awsvpc would allow 2 per large instance); workers only dial
  # out. Fargate: awsvpc is the only mode, and cpu/memory are set on the task.
  requires_compatibilities = [local.fargate ? "FARGATE" : "EC2"]
  network_mode             = local.fargate ? "awsvpc" : "bridge"
  cpu                      = local.fargate ? tostring(var.worker_cpu) : null
  memory                   = local.fargate ? tostring(var.worker_memory_limit) : null
  execution_role_arn       = aws_iam_role.worker_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  dynamic "volume" {
    for_each = local.shared_volumes
    content {
      name = volume.value.name
      efs_volume_configuration {
        file_system_id     = volume.value.efs.file_system_id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = volume.value.efs.access_point_id
          iam             = "DISABLED"
        }
      }
    }
  }

  container_definitions = jsonencode([{
    name              = "worker"
    image             = "${local.worker_image}:${each.value}"
    essential         = true
    cpu               = var.worker_cpu
    memoryReservation = var.worker_memory_reservation
    memory            = var.worker_memory_limit
    # The controller adds the assignment (WORCA_CONTROLLER_URL, token, scope, id) per task.
    environment = [for k, v in {
      WORCA_HOME          = "/worca"
      WORCA_PROJECTS_ROOT = "/projects"
      WORCA_CONTAINER     = "1"
      TZ                  = var.timezone
    } : { name = k, value = v }]
    secrets          = [for k in var.worker_env_secrets : { name = k, valueFrom = "${local.ssm_arn}/worker/${k}" }]
    mountPoints      = local.shared_mounts
    stopTimeout      = 30
    logConfiguration = local.log
  }])
}
