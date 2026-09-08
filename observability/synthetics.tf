# Monitores sinteticos de uptime (US-F3-10). Batem no endpoint PUBLICO — o
# API Gateway —, e nao no cluster: e assim que o cliente enxerga o sistema.
#
# Todo o stage e opcional: sem as chaves do Datadog, `count = 0` e nada e
# criado (o CI/CD segue verde antes de existir conta).

terraform {
  required_version = ">= 1.9"
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.39"
    }
  }
}

variable "datadog_api_key" {
  description = "API key do Datadog. Vazio = nao provisiona monitores."
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Application key do Datadog."
  type        = string
  default     = ""
  sensitive   = true
}

variable "gateway_url" {
  description = "URL publica do API Gateway (output `api_base_url` do stage gateway/)."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Destino das notificacoes dos monitores (ex.: 'email@dominio')."
  type        = string
  default     = ""
}

locals {
  habilitado = var.datadog_api_key != "" && var.gateway_url != ""
  destino    = var.alert_email != "" ? "@${var.alert_email}" : ""
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}

# Liveness: a API responde? Roda de 1 em 1 minuto, de duas regioes.
resource "datadog_synthetics_test" "health" {
  count = local.habilitado ? 1 : 0

  name      = "oficina — /health (liveness)"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = ["aws:us-east-1", "aws:sa-east-1"]
  message   = "A API da oficina nao respondeu 200 em /health. ${local.destino}"
  tags      = ["projeto:oficina-mecanica", "fase:3", "story:us-f3-10"]

  request_definition {
    method = "GET"
    url    = "${var.gateway_url}/health"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "2000"
  }

  options_list {
    tick_every = 60
    retry {
      count    = 2
      interval = 5000
    }
  }
}

# Readiness: a API consegue falar com o banco? Separado do liveness para
# distinguir "app fora" de "dependencia fora".
resource "datadog_synthetics_test" "ready" {
  count = local.habilitado ? 1 : 0

  name      = "oficina — /health/ready (dependencias)"
  type      = "api"
  subtype   = "http"
  status    = "live"
  locations = ["aws:us-east-1"]
  message   = "A API da oficina esta up mas nao pronta (banco?). ${local.destino}"
  tags      = ["projeto:oficina-mecanica", "fase:3", "story:us-f3-10"]

  request_definition {
    method = "GET"
    url    = "${var.gateway_url}/health/ready"
  }

  assertion {
    type     = "statusCode"
    operator = "is"
    target   = "200"
  }

  options_list {
    tick_every = 300
  }
}

output "synthetics_habilitado" {
  description = "Se os monitores foram provisionados (exige chaves do Datadog + URL do gateway)."
  # nonsensitive: o booleano deriva da API key mas nao a revela.
  value = nonsensitive(local.habilitado)
}
