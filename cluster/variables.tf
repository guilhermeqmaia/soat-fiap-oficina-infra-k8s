# Stage cluster — EKS: variaveis de entrada.

variable "aws_region" {
  description = "Regiao AWS. O Learner Lab da AWS Academy opera em us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo de nomes."
  type        = string
  default     = "oficina-mecanica"
}

variable "lab_role_arn" {
  description = "AWS Academy: ARN da LabRole, usada como role do cluster E do node group (o lab nao permite criar IAM roles). Vazio = conta propria: o stage cria as roles (iam.tf)."
  type        = string
  default     = ""

  validation {
    condition     = var.lab_role_arn == "" || startswith(var.lab_role_arn, "arn:aws:iam:")
    error_message = "lab_role_arn deve ser vazio (conta propria) ou um ARN de IAM role (arn:aws:iam::<conta>:role/LabRole)."
  }
}

variable "cluster_admin_arns" {
  description = "ARNs IAM (usuarios/roles) que recebem AmazonEKSClusterAdminPolicy via access entry — alem de quem roda o apply."
  type        = list(string)
  default     = []
}

variable "kubernetes_version" {
  description = "Versao do Kubernetes do EKS. Manter em suporte PADRAO: versoes em extended support custam 6x no control plane (US$ 0,60/h vs 0,10/h — visto na conta em 09/2026 com a 1.31)."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "CIDR da VPC. Subnets /20 sao derivadas dele (2 publicas + 2 privadas)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "Tipos de instancia do managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Nodes desejados. O HPA escala PODS; nodes escalam pelo scaling_config."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimo de nodes (>= 2 para HA multi-AZ)."
  type        = number
  default     = 2

  validation {
    condition     = var.node_min_size >= 2
    error_message = "node_min_size deve ser >= 2 — HA multi-AZ prometida no plano da Fase 3."
  }
}

variable "node_max_size" {
  description = "Maximo de nodes."
  type        = number
  default     = 4
}

variable "log_retention_days" {
  description = "Retencao do log group do control plane."
  type        = number
  default     = 7
}
