# Dashboards como codigo (US-F3-11). Consomem os sinais publicados pela
# aplicacao em /metrics (US-F3-10) e as metricas do agente no cluster.
#
# Como todo o stage, so materializa com as chaves do Datadog configuradas.

locals {
  # Nome da metrica no Datadog: o scrape OpenMetrics prefixa com o namespace
  # da checagem. `oficina_os_transicoes_total` vira `oficina.os_transicoes.count`
  # no formato do Datadog (ver observability/README.md).
  m_transicoes   = "oficina.os_transicoes.count"
  m_integracoes  = "oficina.integracoes.count"
  m_latencia     = "oficina.http_request_duration_seconds" # distribuicao (p95/p99 nativos)
  m_tempo_status = "oficina.os_tempo_no_status_seconds"    # distribuicao
}

# ---------------------------------------------------------------------------
# Dashboard de NEGOCIO — os tres paineis exigidos pelo enunciado.
# ---------------------------------------------------------------------------
resource "datadog_dashboard" "negocio" {
  count = local.habilitado ? 1 : 0

  title       = "Oficina — Operacao (negocio)"
  description = "Volume de OS, tempo por status e erros de integracao (US-F3-11)."
  layout_type = "ordered"
  tags        = ["team:oficina-mecanica"] # a API de dashboards so aceita as chaves team/ai

  # 1) Volume diario de ordens de servico, quebrado por status de destino.
  widget {
    timeseries_definition {
      title = "Volume diario de OS (por status de destino)"
      request {
        q            = "sum:${local.m_transicoes}{*} by {para}.as_count().rollup(sum, 86400)"
        display_type = "bars"
      }
    }
  }

  # 2) Tempo medio de execucao por status (Diagnostico, Execucao, Finalizacao).
  widget {
    timeseries_definition {
      title = "Tempo medio por status (p50 e p95)"
      request {
        q            = "p50:${local.m_tempo_status}{*} by {status}"
        display_type = "line"
      }
      request {
        q            = "p95:${local.m_tempo_status}{*} by {status}"
        display_type = "line"
      }
    }
  }

  # 3) Erros e falhas nas integracoes.
  widget {
    timeseries_definition {
      title = "Erros de integracao (webhook de notificacao, auth)"
      request {
        q            = "sum:${local.m_integracoes}{resultado:falha} by {integracao}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    query_value_definition {
      title = "Taxa de sucesso das integracoes (24h)"
      request {
        q = "sum:${local.m_integracoes}{resultado:sucesso}.as_count() / sum:${local.m_integracoes}{*}.as_count() * 100"
        conditional_formats {
          comparator = "<"
          value      = 95
          palette    = "white_on_red"
        }
        conditional_formats {
          comparator = ">="
          value      = 95
          palette    = "white_on_green"
        }
      }
      precision = 1
    }
  }
}

# ---------------------------------------------------------------------------
# Dashboard TECNICO — saude da plataforma (latencia, recursos, uptime).
# ---------------------------------------------------------------------------
resource "datadog_dashboard" "tecnico" {
  count = local.habilitado ? 1 : 0

  title       = "Oficina — Saude tecnica"
  description = "Latencia, 5xx, CPU/memoria do EKS e uptime (US-F3-10/11)."
  layout_type = "ordered"
  tags        = ["team:oficina-mecanica"] # a API de dashboards so aceita as chaves team/ai

  widget {
    timeseries_definition {
      title = "Latencia da API por rota (p95 / p99)"
      request {
        q            = "p95:${local.m_latencia}{*} by {route}"
        display_type = "line"
      }
      request {
        q            = "p99:${local.m_latencia}{*} by {route}"
        display_type = "line"
      }
      marker {
        display_type = "error dashed"
        value        = "y = 0.5" # SLO de leitura da suite perf/ (p95 < 500ms)
        label        = "SLO p95 leitura"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Taxa de 5xx por rota"
      request {
        q            = "sum:oficina.http_request_duration_seconds.count{status:5*} by {route}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "CPU e memoria dos pods (EKS)"
      request {
        q            = "avg:kubernetes.cpu.usage.total{kube_namespace:oficina} by {pod_name} / 1000000" # nanocores -> millicores
        display_type = "line"
      }
      request {
        q            = "avg:kubernetes.memory.usage{kube_namespace:oficina} by {pod_name}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Replicas do deployment (efeito do HPA)"
      request {
        q            = "avg:kubernetes_state.deployment.replicas_available{kube_deployment:oficina-app}"
        display_type = "area"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "API Gateway — latencia de borda e erros"
      request {
        q            = "avg:aws.apigateway.latency{*}"
        display_type = "line"
      }
      request {
        q            = "sum:aws.apigateway.5xxerror{*}.as_count()"
        display_type = "bars"
      }
    }
  }
}

# nonsensitive: as URLs nao contem segredo — a marca vem de `local.habilitado`,
# que deriva da API key.
output "dashboard_negocio_url" {
  description = "URL do dashboard de negocio (analise ao vivo na demo)."
  value       = nonsensitive(local.habilitado ? datadog_dashboard.negocio[0].url : "")
}

output "dashboard_tecnico_url" {
  description = "URL do dashboard tecnico."
  value       = nonsensitive(local.habilitado ? datadog_dashboard.tecnico[0].url : "")
}
