# AWS Academy: credenciais temporarias do Learner Lab (inclui AWS_SESSION_TOKEN).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Fase      = "fase-3"
      Story     = "US-F3-05"
      ManagedBy = "terraform"
    }
  }
}
