# Task roles. Each task has an EXECUTION role (what ECS does for it: pull the image, write its log,
# read its secrets from SSM) and, for the controller only, a TASK role (what its code may call).
# Workers have no task role: agents get no AWS credentials.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  ssm_prefix = "/worca/${var.environment}"
  ssm_arn    = "arn:aws:ssm:${var.region}:${local.account_id}:parameter${local.ssm_prefix}"
}

data "aws_iam_policy_document" "tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.region}:${local.account_id}:*"]
    }
  }
}

# --- Execution roles ---

resource "aws_iam_role" "controller_execution" {
  name_prefix        = "${var.name}-ctl-exec-"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
}

resource "aws_iam_role" "worker_execution" {
  name_prefix        = "${var.name}-wrk-exec-"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  for_each   = { controller = aws_iam_role.controller_execution.name, worker = aws_iam_role.worker_execution.name }
  role       = each.value
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# SecureStrings with the AWS-managed key need only ssm:GetParameters.
resource "aws_iam_role_policy" "controller_secrets" {
  name = "ssm-read"
  role = aws_iam_role.controller_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters"]
      Resource = ["${local.ssm_arn}/controller/*", "${local.ssm_arn}/auth/*"]
    }]
  })
}

resource "aws_iam_role_policy" "worker_secrets" {
  name = "ssm-read"
  role = aws_iam_role.worker_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters"]
      Resource = ["${local.ssm_arn}/worker/*"]
    }]
  })
}

# --- The controller's task role: start, watch and stop worker tasks (Worca's ecs executor) ---

resource "aws_iam_role" "controller" {
  name_prefix        = "${var.name}-controller-"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
}

resource "aws_iam_role_policy" "controller_ecs" {
  name = "worca-ecs-executor"
  role = aws_iam_role.controller.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunWorkers"
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = ["arn:aws:ecs:${var.region}:${local.account_id}:task-definition/${var.name}-worker-*"]
        Condition = {
          ArnEquals = { "ecs:cluster" = aws_ecs_cluster.this.arn }
        }
      },
      {
        Sid      = "TagWorkersAtLaunch"
        Effect   = "Allow"
        Action   = ["ecs:TagResource"]
        Resource = ["arn:aws:ecs:${var.region}:${local.account_id}:task/${var.name}/*"]
        Condition = {
          StringEquals = { "ecs:CreateAction" = "RunTask" }
        }
      },
      {
        Sid      = "WatchAndStopWorkers"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks", "ecs:StopTask"]
        Resource = ["arn:aws:ecs:${var.region}:${local.account_id}:task/${var.name}/*"]
      },
      {
        Sid      = "ListWorkers"
        Effect   = "Allow"
        Action   = ["ecs:ListTasks"]
        Resource = ["*"]
        Condition = {
          ArnEquals = { "ecs:cluster" = aws_ecs_cluster.this.arn }
        }
      },
      {
        Sid      = "HandWorkersTheirExecutionRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.worker_execution.arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
    ]
  })
}
