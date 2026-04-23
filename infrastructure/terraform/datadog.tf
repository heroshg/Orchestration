# ── AWS Integration IAM Role ──────────────────────────────────────────────────
# Permite ao Datadog ler métricas do CloudWatch para todos os serviços AWS

resource "aws_iam_role" "datadog_aws" {
  name = "${local.name_prefix}-datadog-aws-integration"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::464622532012:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = var.datadog_external_id }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "datadog_aws" {
  name = "DatadogAWSReadAccess"
  role = aws_iam_role.datadog_aws.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "apigateway:GET",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "dynamodb:DescribeTable",
        "dynamodb:ListTables",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "ecs:DescribeClusters",
        "ecs:DescribeContainerInstances",
        "ecs:DescribeServices",
        "ecs:DescribeTasks",
        "ecs:DescribeTaskDefinition",
        "ecs:ListClusters",
        "ecs:ListContainerInstances",
        "ecs:ListServices",
        "ecs:ListTaskDefinitions",
        "ecs:ListTasks",
        "lambda:GetFunction",
        "lambda:ListFunctions",
        "logs:DescribeLogGroups",
        "sqs:GetQueueAttributes",
        "sqs:ListQueues",
        "tag:GetResources",
        "tag:GetTagKeys",
        "tag:GetTagValues",
      ]
      Resource = "*"
    }]
  })
}

# ── Datadog Agent Task Role ───────────────────────────────────────────────────

resource "aws_iam_role" "datadog_agent_task" {
  name = "${local.name_prefix}-datadog-agent-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "datadog_agent_task" {
  name = "DatadogAgentECSAccess"
  role = aws_iam_role.datadog_agent_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:ListClusters",
        "ecs:ListContainerInstances",
        "ecs:DescribeContainerInstances",
      ]
      Resource = "*"
    }]
  })
}

# ── Datadog Agent ECS Service ─────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "datadog_agent" {
  name              = "/ecs/${local.name_prefix}-datadog-agent"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_ecs_task_definition" "datadog_agent" {
  family        = "${local.name_prefix}-datadog-agent"
  network_mode  = "host"
  task_role_arn = aws_iam_role.datadog_agent_task.arn

  volume {
    name      = "docker_sock"
    host_path = "/var/run/docker.sock"
  }
  volume {
    name      = "proc"
    host_path = "/proc/"
  }
  volume {
    name      = "cgroup"
    host_path = "/sys/fs/cgroup/"
  }

  container_definitions = jsonencode([{
    name              = "datadog-agent"
    image             = "public.ecr.aws/datadog/agent:7"
    essential         = true
    memoryReservation = 192

    environment = [
      { name = "DD_API_KEY",                           value = var.dd_api_key },
      { name = "DD_SITE",                              value = var.dd_site },
      { name = "DD_ENV",                               value = var.environment },
      { name = "DD_TAGS",                              value = "project:fiapcloudgames env:${var.environment}" },
      { name = "DD_APM_ENABLED",                       value = "true" },
      { name = "DD_APM_NON_LOCAL_TRAFFIC",             value = "true" },
      { name = "DD_LOGS_ENABLED",                      value = "true" },
      { name = "DD_LOGS_CONFIG_CONTAINER_COLLECT_ALL", value = "true" },
      { name = "DD_DOGSTATSD_NON_LOCAL_TRAFFIC",       value = "true" },
      { name = "DD_PROCESS_AGENT_ENABLED",             value = "false" },
      { name = "DD_CONTAINER_EXCLUDE",                 value = "name:datadog-agent" },
      { name = "DD_ECS_COLLECT_RESOURCE_TAGS_EC2",     value = "true" },
      { name = "DD_HOSTNAME_TRUST_UTS_NAMESPACE",      value = "true" },
    ]

    mountPoints = [
      { containerPath = "/var/run/docker.sock", sourceVolume = "docker_sock", readOnly = true },
      { containerPath = "/host/proc",           sourceVolume = "proc",        readOnly = true },
      { containerPath = "/host/sys/fs/cgroup",  sourceVolume = "cgroup",      readOnly = true },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${local.name_prefix}-datadog-agent"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_service" "datadog_agent" {
  name                               = "${local.name_prefix}-datadog-agent"
  cluster                            = aws_ecs_cluster.fcg.id
  task_definition                    = aws_ecs_task_definition.datadog_agent.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  tags                               = local.common_tags
}
