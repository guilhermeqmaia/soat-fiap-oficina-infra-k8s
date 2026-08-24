# Stage 03 — API Gateway: configuracao do provider AWS.
# AWS Academy: credenciais temporarias do Learner Lab (aws configure ou
# variaveis AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Fase      = "fase-3"
      Story     = "US-F3-02"
      ManagedBy = "terraform"
    }
  }
}
