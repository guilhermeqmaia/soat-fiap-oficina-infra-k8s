# Stage 03 — API Gateway: locals derivados.
locals {
  gateway_name = "${var.project_name}-gateway"

  # authorizer_uri exige o formato "invoke ARN" do API Gateway (nao o ARN puro).
  authorizer_invoke_uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.auth_lambda_arn}/invocations"

  # Rotas publicas encaminhadas ao backend no EKS sem authorizer.
  # Mapeadas 1:1 com os endpoints @Public() do monolito; o path da requisicao
  # e repassado como recebido (passthrough das integracoes privadas).
  public_backend_route_keys = [
    "GET /health",
    "GET /health/ready",
    "GET /ordens-servico/numero/{numero}/status",
    "POST /webhooks/ordens-servico/{id}/aprovacao",
    "GET /webhooks/ordens-servico/{id}/aprovar",
    "GET /webhooks/ordens-servico/{id}/rejeitar",
  ]

  # Formato JSON dos access logs (exportados para observabilidade — US-F3-10).
  access_log_format = jsonencode({
    requestId        = "$context.requestId"
    ip               = "$context.identity.sourceIp"
    requestTime      = "$context.requestTime"
    routeKey         = "$context.routeKey"
    status           = "$context.status"
    latencyMs        = "$context.responseLatency"
    integrationError = "$context.integrationErrorMessage"
    authorizerError  = "$context.authorizer.error"
    userAgent        = "$context.identity.userAgent"
  })
}
