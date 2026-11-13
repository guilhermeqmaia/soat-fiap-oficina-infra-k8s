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
      title = "Tempo medio por status (Diagnostico, Execucao, Finalizacao)"
      # Media = soma / contagem do histograma (OpenMetrics). Nao depende de
      # percentil habilitado na distribuicao — que so existe apos a 1a amostra.
      request {
        q            = "sum:${local.m_tempo_status}.sum{*} by {status}.as_count() / sum:${local.m_tempo_status}.count{*} by {status}.as_count()"
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

# ---------------------------------------------------------------------------
# Dashboard do FLUXO DISTRIBUIDO (US-F4-16) — saga orquestrada pelo OS Service
# e chamadas HTTP diretas entre os servicos (RFC-0008: sem filas/DLQ).
# Fontes (os-service /metrics, mapeadas em datadog-values.yaml):
#   oficina_os_saga_passos_total, oficina_os_saga_passo_duracao_seconds,
#   oficina_os_sagas, oficina_os_sagas_paradas, oficina_http_interno_total,
#   oficina_http_interno_duracao_seconds, oficina_callbacks_total.
# ---------------------------------------------------------------------------
locals {
  # Contadores viram <nome>.count; histogramas viram distribuicoes (media =
  # sum/count; p95 so onde metrics.tf habilita percentis); gauges sem sufixo.
  m_saga_passos      = "oficina.os_saga_passos.count"
  m_saga_duracao     = "oficina.os_saga_passo_duracao_seconds"
  m_sagas            = "oficina.os_sagas"
  m_sagas_paradas    = "oficina.os_sagas_paradas"
  m_http_interno     = "oficina.http_interno.count"
  m_http_interno_dur = "oficina.http_interno_duracao_seconds"
  m_callbacks        = "oficina.callbacks.count"
  # Segundos — mesmo limite do monitor latencia_entre_servicos.
  limite_p95_interno = 2
}

resource "datadog_dashboard" "fluxo_distribuido" {
  count = local.habilitado ? 1 : 0

  title       = "Oficina — Fluxo distribuído"
  description = "Saga da OS (passos, tempo, compensacoes, sagas paradas), chamadas HTTP entre servicos (p95 e erro por origem->destino) e callbacks (US-F4-16)."
  layout_type = "ordered"
  tags        = ["team:oficina-mecanica"]

  # --- Saga ----------------------------------------------------------------
  widget {
    query_value_definition {
      title = "Sagas paradas agora"
      request {
        q          = "max:${local.m_sagas_paradas}{*}"
        aggregator = "last"
        conditional_formats {
          comparator = ">"
          value      = 0
          palette    = "white_on_red"
        }
        conditional_formats {
          comparator = "<="
          value      = 0
          palette    = "white_on_green"
        }
      }
      precision = 0
    }
  }

  widget {
    timeseries_definition {
      title = "Sagas por status (gauge)"
      request {
        q            = "max:${local.m_sagas}{*} by {status}"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Sagas por passo (eventos processados)"
      request {
        q            = "sum:${local.m_saga_passos}{*} by {passo}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Tempo medio por passo da saga"
      # Media = soma / contagem (nao depende de percentil habilitado).
      request {
        q            = "sum:${local.m_saga_duracao}.sum{*} by {passo}.as_count() / sum:${local.m_saga_duracao}.count{*} by {passo}.as_count()"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Compensacoes (saga entrou em COMPENSANDO / terminou CANCELADA)"
      request {
        q            = "sum:${local.m_saga_passos}{resultado:compensando} by {passo}.as_count()"
        display_type = "bars"
      }
      request {
        q            = "sum:${local.m_saga_passos}{resultado:cancelada} by {passo}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Sagas paradas (historico)"
      request {
        q            = "max:${local.m_sagas_paradas}{*}"
        display_type = "area"
      }
    }
  }

  # --- Chamadas HTTP entre servicos ----------------------------------------
  widget {
    timeseries_definition {
      title = "Latencia p95 por par origem -> destino"
      request {
        q            = "p95:${local.m_http_interno_dur}{*} by {origem,destino}"
        display_type = "line"
      }
      marker {
        display_type = "error dashed"
        value        = "y = ${local.limite_p95_interno}"
        label        = "alerta p95 > 2 s"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Taxa de erro por par origem -> destino (%) — esgotado + erro"
      # `recusa` (409 de negocio) nao e erro de infraestrutura; fica no painel de resultados.
      request {
        q            = "(sum:${local.m_http_interno}{resultado:esgotado} by {origem,destino}.as_count() + sum:${local.m_http_interno}{resultado:erro} by {origem,destino}.as_count()) / sum:${local.m_http_interno}{*} by {origem,destino}.as_count() * 100"
        display_type = "line"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "Chamadas entre servicos por rota e resultado"
      request {
        q            = "sum:${local.m_http_interno}{*} by {destino,rota,resultado}.as_count()"
        display_type = "bars"
      }
    }
  }

  # --- Callbacks e erros por servico ---------------------------------------
  widget {
    timeseries_definition {
      title = "Callbacks por type e resultado"
      request {
        q            = "sum:${local.m_callbacks}{*} by {type,resultado}.as_count()"
        display_type = "bars"
      }
    }
  }

  widget {
    timeseries_definition {
      title = "5xx por servico"
      request {
        q            = "sum:${local.m_latencia}.count{status:5*} by {service}.as_count()"
        display_type = "bars"
      }
    }
  }
}

output "dashboard_fluxo_distribuido_url" {
  description = "URL do dashboard do fluxo distribuido (US-F4-16)."
  value       = nonsensitive(local.habilitado ? datadog_dashboard.fluxo_distribuido[0].url : "")
}
