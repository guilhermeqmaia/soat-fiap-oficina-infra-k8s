# Stage cluster — EKS: restricoes de versao. Blocos provider {} em providers.tf.
terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
