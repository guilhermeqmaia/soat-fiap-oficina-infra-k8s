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
