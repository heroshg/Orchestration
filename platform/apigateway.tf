# Spec 01 — AWS API Gateway (HTTP API) gerenciado + VPC Link — gateway central cloud-native.
# Substitui o Kong (validado na sessão anterior, mas fora de escopo agora — ver 00-overview.md
# "Mudança de escopo do gateway"). Cada serviço declara a PRÓPRIA rota/integração na Terraform
# do seu repo (independência — spec 01/07), referenciando api_id/vpc_link_id publicados no SSM
# (ssm.tf) — nunca editando este arquivo.
# ⚠️ Não aplicado nesta sessão (aws/terraform indisponíveis no shell + creds do lab rotativas —
# ver "Estado da execução" em specs/phase2/00-overview.md). Plano para o próximo `terraform apply`.

resource "aws_security_group" "vpc_link" {
  name        = "fcg-apigw-vpclink-sg"
  description = "SG do VPC Link do API Gateway - alcanca os NLBs internos dos servicos na VPC"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Alcanca os Services internos (NLB) dos servicos, porta do container .NET"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  tags = {
    Project = "FiapCloudGames"
  }
}

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "fcg-vpc-link"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = module.vpc.private_subnets

  tags = {
    Project = "FiapCloudGames"
  }
}

resource "aws_apigatewayv2_api" "this" {
  name          = "fcg-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = {
    Project = "FiapCloudGames"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 50
  }

  tags = {
    Project = "FiapCloudGames"
  }
}

# Rotas/integrações por serviço (ex.: ANY /api/games/{proxy+} → VPC_LINK → NLB do catalog-api)
# ficam na Terraform de cada repo (UsersAPI/infra, CatalogAPI/infra, PaymentsAPI/infra),
# usando `aws_apigatewayv2_integration` (tipo HTTP_PROXY, connection_type VPC_LINK) +
# `aws_apigatewayv2_route`, lendo api_id/vpc_link_id via SSM (spec 01/07). Uma rota nova é
# uma mudança só no repo do serviço.
