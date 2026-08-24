# Stage 03 — API Gateway: restricoes de versao do Terraform e do provider.
# Mantido sem blocos `provider {}` (esses ficam em providers.tf) para que
# `terraform validate` cheque apenas as constraints.
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
