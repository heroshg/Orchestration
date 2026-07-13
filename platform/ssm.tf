# Publica referências compartilhadas no SSM Parameter Store (spec 01 / independência).
# Os repos de serviço leem via `data "aws_ssm_parameter"` — sem compartilhar tfstate.
# OBS: no Learner Lab NÃO há oidc_provider_arn (enable_irsa=false).

locals {
  ssm_prefix = "/fcg/platform"
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "${local.ssm_prefix}/eks/cluster_name"
  type  = "String"
  value = aws_eks_cluster.this.name
}

resource "aws_ssm_parameter" "cluster_endpoint" {
  name  = "${local.ssm_prefix}/eks/cluster_endpoint"
  type  = "String"
  value = aws_eks_cluster.this.endpoint
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "${local.ssm_prefix}/vpc/id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "private_subnets" {
  name  = "${local.ssm_prefix}/vpc/private_subnets"
  type  = "StringList"
  value = join(",", module.vpc.private_subnets)
}

# Subnets públicas (roteiam pro Internet Gateway) — necessárias pro RDS/OpenSearch "dev público"
# (spec 04/06): publicly_accessible=true sozinho não basta, o subnet group precisa estar em subnet
# com rota de IGW, senão o IP público fica sem rota de volta (timeout de conexão).
resource "aws_ssm_parameter" "public_subnets" {
  name  = "${local.ssm_prefix}/vpc/public_subnets"
  type  = "StringList"
  value = join(",", module.vpc.public_subnets)
}

resource "aws_ssm_parameter" "lab_role_arn" {
  name  = "${local.ssm_prefix}/iam/lab_role_arn"
  type  = "String"
  value = var.lab_role_arn
}

# URLs dos repositórios ECR criados pela plataforma (ver ecr.tf)
resource "aws_ssm_parameter" "ecr_urls" {
  for_each = aws_ecr_repository.repos
  name     = "${local.ssm_prefix}/ecr/${each.key}_url"
  type     = "String"
  value    = each.value.repository_url
}

# API Gateway (HTTP API) + VPC Link (ver apigateway.tf) — cada serviço lê estes parâmetros
# para declarar a própria rota/integração (spec 01/07), sem editar este repo.
resource "aws_ssm_parameter" "apigw_api_id" {
  name  = "${local.ssm_prefix}/apigw/api_id"
  type  = "String"
  value = aws_apigatewayv2_api.this.id
}

resource "aws_ssm_parameter" "apigw_api_endpoint" {
  name  = "${local.ssm_prefix}/apigw/api_endpoint"
  type  = "String"
  value = aws_apigatewayv2_api.this.api_endpoint
}

resource "aws_ssm_parameter" "apigw_vpc_link_id" {
  name  = "${local.ssm_prefix}/apigw/vpc_link_id"
  type  = "String"
  value = aws_apigatewayv2_vpc_link.this.id
}
