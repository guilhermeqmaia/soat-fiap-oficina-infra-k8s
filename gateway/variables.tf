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

  # Regiao do ARN precisa bater com var.aws_region: um tfvars colado de outro
  # ambiente passaria no plan e so falharia em runtime (500 no authorizer).
  validation {
    condition     = split(":", var.auth_lambda_arn)[3] == var.aws_region
    error_message = "A regiao do auth_lambda_arn difere de aws_region — o authorizer falharia em runtime."
  }
}

variable "backend_listener_arn" {
  description = "TRANSICAO (Fase 3): ARN do listener do NLB criado pelo Service LoadBalancer do monolito. Quando informado, as rotas do OS Service usam esse listener em vez do target group NodePort do NLB unico (ate a US-F4-06 trocar o Service para NodePort). Vazio = NLB unico para os 3 servicos."
  type        = string
  default     = ""

  validation {
    condition     = var.backend_listener_arn == "" || startswith(var.backend_listener_arn, "arn:aws:elasticloadbalancing:")
    error_message = "backend_listener_arn deve ser vazio ou um ARN de listener de ELB."
  }
}

variable "vpc_id" {
  description = "VPC do cluster (output vpc_id do stage cluster) — target groups do NLB unico (ADR-0013)."
  type        = string

  validation {
    condition     = startswith(var.vpc_id, "vpc-")
    error_message = "vpc_id deve ser um id de VPC (vpc-...)."
  }
}

variable "cluster_name" {
  description = "Nome do cluster EKS (output cluster_name do stage cluster) — usado para achar o Auto Scaling Group dos nodes e registra-lo nos target groups."
  type        = string
  default     = "oficina-mecanica-eks"
}

variable "node_group_name" {
  description = "Nome do managed node group (stage cluster)."
  type        = string
  default     = "oficina-mecanica-nodes"
}

variable "services" {
  description = "Microsservicos atras do gateway (ADR-0013): porta do container, NodePort fixo (overlay k8s-aws de cada repo) e prefixos de rota. O NLB unico tem um listener/target group por servico."
  type = map(object({
    port      = number
    node_port = number
    prefixes  = list(string)
  }))
  default = {
    os = {
      port      = 3000
      node_port = 30080
      prefixes  = ["/ordens-servico", "/clientes", "/veiculos", "/usuario", "/notificacoes", "/auth/me"]
    }
    billing = {
      port      = 3001
      node_port = 30081
      prefixes  = ["/orcamentos", "/pagamentos"]
    }
    execucao = {
      port      = 3002
      node_port = 30082
      prefixes  = ["/execucao", "/catalogo", "/estoque"]
    }
  }
}

variable "vpc_link_subnet_ids" {
  description = "Subnets (privadas) da VPC do EKS onde o VPC Link cria suas ENIs (US-F3-05). Minimo 2, em AZs distintas, cobrindo as AZs do ALB interno."
  type        = list(string)

  # 1 subnet = trafego cross-AZ pago + API inteira cai junto com a AZ,
  # contrariando o requisito de HA multi-AZ do plano da Fase 3.
  validation {
    condition     = length(var.vpc_link_subnet_ids) >= 2
    error_message = "Informe ao menos 2 subnets (AZs distintas) para o VPC Link — requisito de HA multi-AZ."
  }
}

variable "vpc_link_security_group_ids" {
  description = "Security groups do VPC Link — precisam liberar saida para o ALB/NLB interno."
  type        = list(string)
}

variable "throttling_rate_limit" {
  description = "Limite sustentado de requisicoes/segundo por rota (throttling do stage). O default cobre a demo e os testes de carga da suite perf/ (que roda ate ~300 rps quando apontada ao gateway); reduza em producao real se quiser um teto mais conservador."
  type        = number
  default     = 400
}

variable "throttling_burst_limit" {
  description = "Pico (burst) de requisicoes permitido por rota (throttling do stage)."
  type        = number
  default     = 800
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
