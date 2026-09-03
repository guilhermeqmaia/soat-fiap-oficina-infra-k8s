# Stage 03 — API Gateway: restricoes de versao do Terraform e do provider.
# Mantido sem blocos `provider {}` (esses ficam em providers.tf) para que
# `terraform validate` cheque apenas as constraints.
terraform {
  # >= 1.9: as validations referenciam outras variaveis (checagem cruzada de
  # regiao do ARN x aws_region).
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
