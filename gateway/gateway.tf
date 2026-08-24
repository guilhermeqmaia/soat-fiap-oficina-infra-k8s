# Stage 03 — API Gateway: HTTP API (v2), VPC Link, stage unico e access logs.
#
# HTTP API (e nao REST API) de proposito: alem de mais barato e simples,
# grava access logs sem exigir a role de conta do CloudWatch — que nao
# poderiamos criar no AWS Academy (IAM restrito a LabRole).

resource "aws_apigatewayv2_api" "this" {
  name          = local.gateway_name
  protocol_type = "HTTP"
  description   = "Entrada unica das APIs da oficina (US-F3-02): /auth na Lambda, rotas sensiveis atras de Lambda Authorizer, backend no EKS via VPC Link."

  cors_configuration {
    allow_origins = var.cors_allowed_origins
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

# Unico caminho publico ate a aplicacao: o backend fica em LB interno na VPC
# e so o gateway (via estas ENIs) o alcanca — sem bypass por fora.
resource "aws_apigatewayv2_vpc_link" "eks" {
  name               = "${local.gateway_name}-eks"
  subnet_ids         = var.vpc_link_subnet_ids
  security_group_ids = var.vpc_link_security_group_ids
}

resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/apigateway/${local.gateway_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  # Throttling de borda: aplicado como default para todas as rotas.
  default_route_settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access_logs.arn
    format          = local.access_log_format
  }
}
