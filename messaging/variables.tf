# Stage messaging — variaveis de entrada.

variable "aws_region" {
  description = "Regiao AWS."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo de tags."
  type        = string
  default     = "oficina-mecanica"
}

variable "name_prefix" {
  description = "Prefixo dos nomes de topicos/filas. `oficina` reproduz os nomes do LocalStack do kit (oficina-os.fifo, ...)."
  type        = string
  default     = "oficina"
}

variable "node_role_name" {
  description = "Nome da IAM role dos nodes do EKS (output node_role_arn do stage cluster, sem o prefixo arn). Quando informado, a policy de publicar/consumir e anexada a ela — sem IRSA os pods herdam a role do node. Vazio no AWS Academy (LabRole ja tem permissao)."
  type        = string
  default     = ""
}

variable "max_receive_count" {
  description = "Tentativas de consumo antes de a mensagem ir para a DLQ (ADR-0009 / RFC-0006)."
  type        = number
  default     = 5
}

variable "visibility_timeout_seconds" {
  description = "Tempo que uma mensagem recebida fica invisivel (janela para o handler processar). Deve exceder o tempo maximo de um handler."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Retencao das filas principais (default 4 dias)."
  type        = number
  default     = 345600
}

variable "dlq_retention_seconds" {
  description = "Retencao das DLQs (default 14 dias — tempo para triagem humana)."
  type        = number
  default     = 1209600
}

variable "alert_email" {
  description = "E-mail para os alarmes de DLQ (CloudWatch -> SNS). Vazio desliga as notificacoes (os alarmes continuam visiveis no console/Datadog)."
  type        = string
  default     = ""
}
