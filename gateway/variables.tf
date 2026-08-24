# Stage 03 — API Gateway: variaveis de entrada.

variable "aws_region" {
  description = "Regiao AWS. O Learner Lab da AWS Academy opera em us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo de nomes para o gateway e recursos associados."
  type        = string
  default     = "oficina-mecanica"
}

variable "auth_lambda_arn" {
  description = "ARN da function Lambda de autenticacao por CPF (US-F3-01). A mesma function atende o POST /auth e o Lambda Authorizer de JWT."
  type        = string

  validation {
    condition     = startswith(var.auth_lambda_arn, "arn:aws:lambda:")
    error_message = "auth_lambda_arn deve ser um ARN de function Lambda (arn:aws:lambda:...)."
  }
}

variable "backend_listener_arn" {
  description = "ARN do listener do ALB/NLB interno que expoe o Service/Ingress da aplicacao no EKS (US-F3-05/06). O gateway alcanca o backend so por dentro da VPC."
  type        = string

  validation {
    condition     = startswith(var.backend_listener_arn, "arn:aws:elasticloadbalancing:")
    error_message = "backend_listener_arn deve ser um ARN de listener de ELB (arn:aws:elasticloadbalancing:...)."
  }
}

variable "vpc_link_subnet_ids" {
  description = "Subnets (privadas) da VPC do EKS onde o VPC Link cria suas ENIs (US-F3-05)."
  type        = list(string)

  validation {
    condition     = length(var.vpc_link_subnet_ids) > 0
    error_message = "Informe ao menos uma subnet para o VPC Link."
  }
}

variable "vpc_link_security_group_ids" {
  description = "Security groups do VPC Link — precisam liberar saida para o ALB/NLB interno."
  type        = list(string)
}

variable "throttling_rate_limit" {
  description = "Limite sustentado de requisicoes/segundo por rota (throttling do stage)."
  type        = number
  default     = 20
}

variable "throttling_burst_limit" {
  description = "Pico (burst) de requisicoes permitido por rota (throttling do stage)."
  type        = number
  default     = 40
}

variable "cors_allowed_origins" {
  description = "Origens permitidas no CORS (UIs admin/cliente). '*' apenas para demo."
  type        = list(string)
  default     = ["*"]
}

variable "authorizer_cache_ttl_seconds" {
  description = "TTL (s) do cache do resultado do authorizer, chaveado pelo header Authorization. 0 desabilita."
  type        = number
  default     = 300
}

variable "log_retention_days" {
  description = "Retencao (dias) do log group de access logs do gateway."
  type        = number
  default     = 7
}
