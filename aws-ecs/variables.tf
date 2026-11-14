variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Name of the ECS cluster and prefix of everything created."
  type        = string
  default     = "worca-ecs"
}

variable "environment" {
  description = "Environment name: tags, and the SSM path /worca/<environment>/ the secrets are read from."
  type        = string
  default     = "poc"
}

variable "vpc_cidr" {
  type    = string
  default = "10.43.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs (the ALB needs subnets in two). The system instance and its database volume are in the first."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

# --- Compute ---

variable "system_instance_type" {
  description = "The always-on, on-demand instance: the Worca controller and oauth2-proxy."
  type        = string
  default     = "t3a.large"
}

variable "worker_launch" {
  description = <<-EOT
    Where worker tasks run:
      ec2           spot instances of the workers Auto Scaling group, scaled from zero by ECS (first worker
                    2-4 minutes from zero, seconds while an instance is up)
      fargate       Fargate, no instances (every worker ~45-90 s: the image is pulled each time)
      fargate-spot  Fargate Spot: ~70% cheaper, may be reclaimed with two minutes' notice (the run pauses)
  EOT
  type        = string
  default     = "fargate"

  validation {
    condition     = contains(["ec2", "fargate", "fargate-spot"], var.worker_launch)
    error_message = "worker_launch must be ec2, fargate or fargate-spot."
  }
}

variable "worker_instance_types" {
  description = "Spot instance types for worker tasks (several types: better spot availability). All x86_64, like the images."
  type        = list(string)
  default     = ["t3a.large", "t3.large", "m5a.large", "m6a.large"]
}

variable "worker_max_instances" {
  description = "Most worker instances managed scaling may start. 0 while no worker runs."
  type        = number
  default     = 2
}

variable "worker_cpu" {
  description = "CPU units per worker task (1024 = one vCPU). Two fit on a large instance. On Fargate, cpu and worker_memory_limit must be a valid Fargate size (1024: 2048-8192 MiB)."
  type        = number
  default     = 1024
}

variable "worker_memory_reservation" {
  description = "MiB reserved per worker task (what placement counts)."
  type        = number
  default     = 2048
}

variable "worker_memory_limit" {
  description = "MiB a worker task may use before it is killed (on Fargate: the task's memory, which is billed)."
  type        = number
  default     = 4096
}

variable "max_workers" {
  description = "WORCA_WORKER_MAX: how many runs and chats may hold a worker at once."
  type        = number
  default     = 4
}

variable "db_volume_size" {
  description = "GB of the controller's database volume (gp3)."
  type        = number
  default     = 10
}

# --- Images (worca-iac/registry/ecr) ---

variable "image_repositories" {
  description = "ECR repository names (registry/ecr outputs `repositories`)."
  type = object({
    controller = string
    worker     = string
  })
  default = {
    controller = "worca-poc/worca"
    worker     = "worca-poc/worca-worker"
  }
}

variable "controller_image_tag" {
  type    = string
  default = "poc"
}

variable "worker_engines" {
  description = "Engine -> worker image tag. One task definition per engine: <name>-worker-<engine>."
  type        = map(string)
  default     = { claude = "poc-claude" }
}

variable "oauth2_proxy_image" {
  type    = string
  default = "quay.io/oauth2-proxy/oauth2-proxy:v7.15.6"
}

# --- Access ---

variable "worca_host" {
  description = "Host name people open, e.g. worca.example.com."
  type        = string
}

variable "route53_zone" {
  description = "Route 53 public zone (its name) that holds worca_host: certificate validation and the record are made in it. Empty: you add them yourself (outputs)."
  type        = string
  default     = ""
}

# --- Worca ---

variable "mock_mode" {
  description = "WORCA_MOCK=1: agents answer with canned replies, no model tokens. For infrastructure tests."
  type        = bool
  default     = false
}

variable "timezone" {
  type    = string
  default = "Europe/Berlin"
}

variable "controller_env_secrets" {
  description = "Environment variables for the controller, each read from SSM /worca/<env>/controller/<NAME> (SecureString)."
  type        = list(string)
  default     = ["CLAUDE_CODE_OAUTH_TOKEN"]
}

variable "worker_env_secrets" {
  description = "Environment variables for worker tasks, each read from SSM /worca/<env>/worker/<NAME>. Keep GitHub tokens out: workers run agents."
  type        = list(string)
  default     = ["CLAUDE_CODE_OAUTH_TOKEN"]
}

variable "allowed_groups" {
  description = "oauth2-proxy allowedGroups (Entra app role values). Empty admits everyone the tenant signs in."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
