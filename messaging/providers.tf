# Stage messaging — provider AWS.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Fase      = "fase-4"
      Story     = "US-F4-02"
      ManagedBy = "terraform"
    }
  }
}
