# Stage 03 — API Gateway: locals derivados.
locals {
  gateway_name = "${var.project_name}-gateway"

  # authorizer_uri exige o formato "invoke ARN" do API Gateway (nao o ARN puro).
  authorizer_invoke_uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.auth_lambda_arn}/invocations"

  # Rotas publicas (sem authorizer) por servico — espelham os endpoints
  # @Public() de cada um. O path e repassado como recebido (HTTP_PROXY).
  public_routes = {
    os = [
      "GET /health",
      "GET /health/ready",
      "GET /ordens-servico/numero/{numero}/status",
      "POST /webhooks/ordens-servico/{id}/aprovacao",
      "GET /webhooks/ordens-servico/{id}/aprovar",
      "GET /webhooks/ordens-servico/{id}/rejeitar",
    ]
    billing = [
      # Mercado Pago chama sem JWT; o Billing valida a assinatura x-signature (ADR-0012).
      "POST /webhooks/mercadopago",
    ]
    execucao = []
  }

  # Rotas protegidas por prefixo: "ANY /orcamentos" e "ANY /orcamentos/{proxy+}".
  protected_routes = merge([
    for svc, cfg in var.services : {
      for prefix in cfg.prefixes : "${svc}:${prefix}" => { service = svc, keys = ["ANY ${prefix}", "ANY ${prefix}/{proxy+}"] }
    }
  ]...)
  protected_route_keys = merge([
    for id, r in local.protected_routes : { for k in r.keys : "${r.service}|${k}" => { service = r.service, key = k } }
  ]...)
  public_route_keys = merge([
    for svc, keys in local.public_routes : { for k in keys : "${svc}|${k}" => { service = svc, key = k } }
  ]...)

  # Integracao do OS Service: transicao (listener do Service LoadBalancer da
  # Fase 3) ou o listener do NLB unico.
  os_listener_arn = var.backend_listener_arn != "" ? var.backend_listener_arn : aws_lb_listener.service["os"].arn
  service_listener_arns = {
    for svc in keys(var.services) : svc => (svc == "os" ? local.os_listener_arn : aws_lb_listener.service[svc].arn)
  }

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
