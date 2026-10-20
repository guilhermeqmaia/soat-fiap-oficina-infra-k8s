# Stage 03 — API Gateway: outputs.

output "api_base_url" {
  description = "URL publica do gateway (entrada unica das APIs). Documentar no README do repo."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_id" {
  description = "ID do HTTP API (util para aws logs / console)."
  value       = aws_apigatewayv2_api.this.id
}

output "authorizer_id" {
  description = "ID do Lambda Authorizer de JWT."
  value       = aws_apigatewayv2_authorizer.jwt.id
}

output "vpc_link_id" {
  description = "ID do VPC Link que conecta o gateway ao LB interno do EKS."
  value       = aws_apigatewayv2_vpc_link.eks.id
}

output "access_log_group" {
  description = "Log group dos access logs do gateway (fonte para a observabilidade — US-F3-10)."
  value       = aws_cloudwatch_log_group.access_logs.name
}


# ─── Fase 4 (US-F4-05) ────────────────────────────────────────────────────────

output "internal_nlb_dns" {
  description = "DNS do NLB interno unico (um listener por servico)."
  value       = aws_lb.internal.dns_name
}

output "service_listeners" {
  description = "Porta do listener e NodePort de cada servico no NLB unico (contrato com o overlay k8s-aws de cada repo)."
  value = {
    for svc, cfg in var.services : svc => {
      listener_arn = aws_lb_listener.service[svc].arn
      port         = cfg.port
      node_port    = cfg.node_port
      prefixes     = cfg.prefixes
    }
  }
}

output "route_map" {
  description = "Prefixos protegidos por servico (documentacao viva do mapa de rotas)."
  value       = { for svc, cfg in var.services : svc => cfg.prefixes }
}
