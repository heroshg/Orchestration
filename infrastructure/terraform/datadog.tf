# ── Datadog AWS Integration ───────────────────────────────────────────────────
# Liga o Datadog à conta AWS via IAM role. O external_id é GERADO pelo Datadog
# (não dá pra forçar um valor) e usado na trust policy da role abaixo.
# Quebra de ciclo: role_name aqui é passado como string literal (não como
# atributo da role), assim o Datadog cria a integration antes da role; a
# trust policy referencia datadog_integration_aws.fcg.external_id (computed).

resource "datadog_integration_aws" "fcg" {
  account_id = data.aws_caller_identity.current.account_id
  role_name  = "${local.name_prefix}-datadog-aws-integration"

  # Sem filter_tags → coleta métricas de todos os recursos da conta
  # Namespaces habilitados por padrão incluem SQS, Lambda, ECS, API Gateway
  account_specific_namespace_rules = {
    sqs             = true
    lambda          = true
    ecs             = true
    api_gateway     = true
    application_elb = false
    dynamodb        = true
  }
}

# ── AWS Integration IAM Role ──────────────────────────────────────────────────
# Permite ao Datadog ler métricas do CloudWatch para todos os serviços AWS.
# A trust policy usa o external_id GERADO pelo Datadog (não um valor estático),
# senão a integration falha silenciosamente ao assumir a role.

resource "aws_iam_role" "datadog_aws" {
  name = "${local.name_prefix}-datadog-aws-integration"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::464622532012:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = datadog_integration_aws.fcg.external_id }
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

# ── Datadog Agent ─────────────────────────────────────────────────────────────
# O agent rodava como serviço ECS (aws_ecs_task_definition/aws_ecs_service) — obsoleto com a
# migração para EKS (spec 01). Em EKS, o agent é um DaemonSet do cluster (Helm chart oficial do
# Datadog), não um recurso Terraform desta conta — ainda não implementado nos k8s-<env>.yaml
# (pendência separada, fora desta spec de limpeza).
