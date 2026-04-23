resource "aws_apigatewayv2_api" "fcg" {
  name          = "fcg-api-gateway-${var.environment}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_stage" "fcg" {
  api_id      = aws_apigatewayv2_api.fcg.id
  name        = var.environment
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  tags = local.common_tags
}

# Integrações com {proxy} — para rotas ANY /{proxy+}
resource "aws_apigatewayv2_integration" "users_api" {
  api_id                 = aws_apigatewayv2_api.fcg.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${aws_eip.ecs.public_ip}:8080/api/users/{proxy}"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_integration" "catalog_api" {
  api_id                 = aws_apigatewayv2_api.fcg.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${aws_eip.ecs.public_ip}:8081/api/games/{proxy}"
  payload_format_version = "1.0"
}

# Integrações sem {proxy} — para rotas exatas (POST /api/users e GET /api/games)
resource "aws_apigatewayv2_integration" "users_api_base" {
  api_id                 = aws_apigatewayv2_api.fcg.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${aws_eip.ecs.public_ip}:8080/api/users"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_integration" "catalog_api_base" {
  api_id                 = aws_apigatewayv2_api.fcg.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${aws_eip.ecs.public_ip}:8081/api/games"
  payload_format_version = "1.0"
}

# Rotas exatas para endpoints base
resource "aws_apigatewayv2_route" "create_user" {
  api_id    = aws_apigatewayv2_api.fcg.id
  route_key = "POST /api/users"
  target    = "integrations/${aws_apigatewayv2_integration.users_api_base.id}"
}

resource "aws_apigatewayv2_route" "get_games" {
  api_id    = aws_apigatewayv2_api.fcg.id
  route_key = "GET /api/games"
  target    = "integrations/${aws_apigatewayv2_integration.catalog_api_base.id}"
}

resource "aws_apigatewayv2_route" "create_game" {
  api_id    = aws_apigatewayv2_api.fcg.id
  route_key = "POST /api/games"
  target    = "integrations/${aws_apigatewayv2_integration.catalog_api_base.id}"
}

# Rotas proxy para demais endpoints (login, getById, purchase, library, etc.)
resource "aws_apigatewayv2_route" "users_proxy" {
  api_id    = aws_apigatewayv2_api.fcg.id
  route_key = "ANY /api/users/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.users_api.id}"
}

resource "aws_apigatewayv2_route" "catalog_proxy" {
  api_id    = aws_apigatewayv2_api.fcg.id
  route_key = "ANY /api/games/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.catalog_api.id}"
}
