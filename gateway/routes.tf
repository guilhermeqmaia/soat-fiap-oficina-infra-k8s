# Stage 03 — API Gateway: authorizer, integracoes e rotas.
#
# Politica de rotas (espelha os endpoints @Public() do monolito):
#   publicas   -> POST /auth (Lambda CPF), /health*, status de OS por numero,
#                 webhooks de aprovacao (protegidos por token/HMAC na aplicacao)
#   sensiveis  -> todo o resto (ANY /{proxy+}) exige JWT validado pelo
#                 Lambda Authorizer antes de encaminhar ao EKS.

# ── Authorizer: a propria Lambda de CPF valida o JWT (US-F3-01) ──────────────

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id                            = aws_apigatewayv2_api.this.id
  name                              = "${var.project_name}-jwt-authorizer"
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = local.authorizer_invoke_uri
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  authorizer_result_ttl_in_seconds  = var.authorizer_cache_ttl_seconds
}

resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.auth_lambda_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.jwt.id}"
}

# ── Rota publica de autenticacao: POST /auth -> Lambda de CPF ────────────────

resource "aws_apigatewayv2_integration" "auth_lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.auth_lambda_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

resource "aws_lambda_permission" "auth" {
  statement_id  = "AllowAPIGatewayInvokeAuth"
  action        = "lambda:InvokeFunction"
  function_name = var.auth_lambda_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*/auth"
}

# ── Backends no EKS via VPC Link: uma integracao por servico (ADR-0013) ──────
# O HTTP API repassa method + path como recebidos ao listener interno do
# servico; as rotas abaixo decidem qual integracao atende cada prefixo.

resource "aws_apigatewayv2_integration" "service" {
  for_each = var.services

  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = local.service_listener_arns[each.key]
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.eks.id
}

# ── Rotas publicas por servico (health, status de OS, webhooks) ──────────────

resource "aws_apigatewayv2_route" "public" {
  for_each = local.public_route_keys

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value.key
  target    = "integrations/${aws_apigatewayv2_integration.service[each.value.service].id}"
}

# ── Rotas sensiveis por prefixo, protegidas pelo authorizer ──────────────────

resource "aws_apigatewayv2_route" "protected" {
  for_each = local.protected_route_keys

  api_id             = aws_apigatewayv2_api.this.id
  route_key          = each.value.key
  target             = "integrations/${aws_apigatewayv2_integration.service[each.value.service].id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

# ── Catch-all protegido -> OS Service (compatibilidade com a Fase 3) ─────────
# Qualquer rota nao listada nos prefixos continua chegando ao monolito/OS
# Service — some conforme a US-F4-06 remove modulos dele.

resource "aws_apigatewayv2_route" "catch_all" {
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.service["os"].id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}
