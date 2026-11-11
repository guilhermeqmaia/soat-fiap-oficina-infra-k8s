# Alertas como codigo (US-F3-11). Cada monitor tem, na `message`, o que
# significa e o primeiro passo do runbook — o alerta chega acionavel, nao so
# como "algo quebrou".
#
# Convencao de severidade:
#   critical -> acorda alguem (fluxo de OS parado, API fora)
#   warning  -> degradacao que precisa de olhar no proximo dia util

# ---------------------------------------------------------------------------
# NEGOCIO — exigido pelo enunciado: falha no processamento de ordens de servico
# ---------------------------------------------------------------------------
# default_zero(): sem nenhum 5xx a serie nao existe e o monitor ficaria em "No Data";
# com zero explicito ele avalia OK (visto em 13/09/2026).
resource "datadog_monitor" "falha_processamento_os" {
  count = local.habilitado ? 1 : 0

  name = "[CRITICO] Falha no processamento de ordens de servico"
  type = "query alert"

  # 5xx nas rotas de OS: excecao nao tratada no fluxo (transicao de status,
  # aprovacao, execucao). Janela de 15min para nao alarmar em falha isolada.
  query = "sum(last_15m):default_zero(sum:oficina.http_request_duration_seconds.count{status:5*,route:/ordens-servico*}.as_count()) > 5"

  message = <<-EOT
    Mais de 5 erros 5xx em rotas de ordem de servico nos ultimos 15 minutos.

    **O que significa:** excecao nao tratada no fluxo de OS (transicao de
    status, aprovacao de orcamento ou execucao). Clientes podem estar sem
    conseguir acompanhar ou aprovar orcamentos.

    **Runbook:**
    1. Dashboard "Oficina — Saude tecnica" -> painel de 5xx por rota
    2. Logs da rota com o `x-correlation-id` da requisicao (US-F3-09)
    3. Se for erro de banco, checar `/health/ready` e o RDS
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 5
    warning  = 2
  }

  tags = ["projeto:oficina-mecanica", "fase:3", "tipo:negocio"]
}

# ---------------------------------------------------------------------------
# NEGOCIO — falha de entrega de notificacao ao cliente
# ---------------------------------------------------------------------------
resource "datadog_monitor" "falha_notificacao" {
  count = local.habilitado ? 1 : 0

  name  = "[AVISO] Falhas na entrega de notificacoes"
  type  = "query alert"
  query = "sum(last_30m):default_zero(sum:oficina.integracoes.count{resultado:falha,integracao:webhook-notificacao}.as_count()) > 3"

  message = <<-EOT
    Notificacoes ao cliente falhando (webhook 4xx/5xx ou timeout).

    **O que significa:** o fluxo da OS segue funcionando, mas o cliente nao
    esta sendo avisado das mudancas de status — o link de aprovacao de
    orcamento pode nao ter chegado.

    **Runbook:**
    1. Dashboard "Oficina — Operacao" -> "Erros de integracao"
    2. Conferir `NOTIFICATION_WEBHOOK_URL` e se o destino esta no ar
    3. As falhas nao bloqueiam a OS: reprocessar apos corrigir o destino
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 3
  }

  tags = ["projeto:oficina-mecanica", "fase:3", "tipo:negocio"]
}

# ---------------------------------------------------------------------------
# PLATAFORMA — latencia acima do SLO
# ---------------------------------------------------------------------------
resource "datadog_monitor" "latencia_slo" {
  count = local.habilitado ? 1 : 0

  name = "[AVISO] Latencia da API acima do SLO (p95 > 500ms)"
  type = "query alert"
  # Mesmo SLO da suite de carga (perf/lib/config.js): p95 < 500ms em leitura.
  query = "avg(last_10m):p95:oficina.http_request_duration_seconds{*} > 0.5"

  message = <<-EOT
    O p95 de latencia passou de 500ms (SLO versionado em `perf/lib/config.js`).

    **Runbook:**
    1. Dashboard tecnico -> latencia por rota (identificar a rota culpada)
    2. Checar se o HPA escalou (painel de replicas) e o CPU dos pods
    3. Se so uma rota degradou, investigar query/banco por trace do APM
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 0.5
    warning  = 0.3
  }

  tags = ["projeto:oficina-mecanica", "fase:3", "tipo:plataforma"]
}

# ---------------------------------------------------------------------------
# PLATAFORMA — recursos do cluster e pods instaveis
# ---------------------------------------------------------------------------
# kubernetes.cpu.usage.total e em NANOcores e cpu.limits em cores: sem o /1e9 a
# razao passa de 1 sempre (alertava com 4% de uso — visto em 13/09/2026).
resource "datadog_monitor" "cpu_pods" {
  count = local.habilitado ? 1 : 0

  name  = "[AVISO] CPU dos pods da aplicacao acima de 85%"
  type  = "query alert"
  query = "avg(last_10m):(avg:kubernetes.cpu.usage.total{kube_namespace:oficina} by {pod_name} / 1000000000) / avg:kubernetes.cpu.limits{kube_namespace:oficina} by {pod_name} > 0.85"

  message = <<-EOT
    Pods perto do limite de CPU. O HPA escala em 70% — se este alerta disparar
    e as replicas ja estiverem no maximo (10), a capacidade do node group
    acabou.

    **Runbook:**
    1. `kubectl -n oficina get hpa oficina-app`
    2. Se `REPLICAS` = max, aumentar `node_max_size` (repo infra-k8s/cluster)
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 0.85
  }

  tags = ["projeto:oficina-mecanica", "fase:3", "tipo:plataforma"]
}

resource "datadog_monitor" "pods_crashloop" {
  count = local.habilitado ? 1 : 0

  name  = "[CRITICO] Pods em CrashLoopBackOff"
  type  = "query alert"
  query = "max(last_10m):max:kubernetes_state.container.restarts{kube_namespace:oficina} by {pod_name} > 5"

  message = <<-EOT
    Container reiniciando em loop no namespace `oficina`.

    **Runbook:**
    1. `kubectl -n oficina describe pod <pod>` e `logs --previous`
    2. Causas comuns: `DATABASE_URL` invalida (Secret dessincronizado do
       Secrets Manager) ou migration pendente
    3. Rollback: `kubectl -n oficina rollout undo deployment/oficina-app`
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 5
  }

  tags = ["projeto:oficina-mecanica", "fase:3", "tipo:plataforma"]
}

# ---------------------------------------------------------------------------
# BORDA — uptime: o alerta e o monitor que o proprio teste sintetico cria
# ("[Synthetics] oficina — /health (liveness)", synthetics.tf). A API de
# monitores rejeita criar/alterar monitores de sintetico diretamente
# ("use Synthetics API instead"), entao a mensagem/runbook ficam no teste.
# ---------------------------------------------------------------------------

# ===========================================================================
# FLUXO DISTRIBUIDO (US-F4-16) — saga do OS Service e chamadas HTTP entre os
# servicos (RFC-0008). Sem alertas de fila/DLQ: o transporte e HTTP direto.
# Cada monitor linka o runbook versionado no os-service (docs/runbooks/).
# ===========================================================================
variable "saga_alerta_parada_min" {
  description = "Minutos que oficina_os_sagas_paradas precisa ficar > 0 para alertar. Use o mesmo valor de SAGA_ALERTA_PARADA_MIN do os-service (padrao 60). Janelas aceitas pelo Datadog: 5, 10, 15, 30, 60, 120 ou 240."
  type        = number
  default     = 60

  validation {
    condition     = contains([5, 10, 15, 30, 60, 120, 240], var.saga_alerta_parada_min)
    error_message = "saga_alerta_parada_min deve ser 5, 10, 15, 30, 60, 120 ou 240 (janelas de avaliacao do Datadog)."
  }
}

locals {
  runbooks           = "https://github.com/guilhermeqmaia/soat-fiap-oficina-os-service/blob/main/docs/runbooks"
  janela_saga_parada = var.saga_alerta_parada_min >= 60 ? "last_${floor(var.saga_alerta_parada_min / 60)}h" : "last_${var.saga_alerta_parada_min}m"
  tags_fluxo         = ["projeto:oficina-mecanica", "fase:4", "tipo:fluxo-distribuido"]
}

# ---------------------------------------------------------------------------
# Saga parada: a gauge ja conta sagas sem avancar ha SAGA_ALERTA_PARADA_MIN e,
# na hora, as que tiveram chamada nao entregue (historico `chamada-falhou`).
# min() na janela: so alerta se ficou > 0 o tempo todo (sem flapping).
# ---------------------------------------------------------------------------
resource "datadog_monitor" "saga_parada" {
  count = local.habilitado ? 1 : 0

  name  = "[CRITICO] Saga de OS parada"
  type  = "query alert"
  query = "min(${local.janela_saga_parada}):default_zero(max:oficina.os_sagas_paradas{*}) > 0"

  message = <<-EOT
    {{value}} saga(s) de OS sem avancar ha mais de ${var.saga_alerta_parada_min} min
    (ou com chamada a Execucao/Billing nao entregue).

    **O que significa:** a OS esta presa num passo da saga — o participante nao
    respondeu, uma compensacao nao foi confirmada ou um callback se perdeu.

    **Runbook:** ${local.runbooks}/saga-parada.md
    1. `GET /ordens-servico/numero/<n>/saga` -> passo e ultimas entradas do historico
    2. Historico com `chamada-falhou`: resolver o participante e
       `POST /admin/sagas/<n>/reprocessar` (${local.runbooks}/saga-reprocessar.md)
    3. Nunca editar `saga_os` a mao
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 0
  }

  tags = local.tags_fluxo
}

# ---------------------------------------------------------------------------
# Retry esgotado: uma chamada do OS a Execucao/Billing falhou 3x (5xx/timeout/rede).
# ---------------------------------------------------------------------------
resource "datadog_monitor" "retry_esgotado" {
  count = local.habilitado ? 1 : 0

  name  = "[CRITICO] Chamada entre servicos com retry esgotado ({{destino.name}})"
  type  = "query alert"
  query = "sum(last_5m):default_zero(sum:oficina.http_interno.count{resultado:esgotado} by {origem,destino}.as_count()) > 0"

  message = <<-EOT
    {{value}} chamada(s) de {{origem.name}} para {{destino.name}} esgotaram as 3 tentativas
    nos ultimos 5 minutos.

    **O que significa:** o destino esta fora, lento (> 5 s) ou respondendo 5xx. A
    saga da OS ficou no passo com `chamada-falhou` e vai aparecer em "Saga parada".

    **Runbook:** ${local.runbooks}/retry-esgotado.md
    1. Dashboard "Oficina — Fluxo distribuído" -> chamadas por rota e resultado
    2. `kubectl -n oficina get pods` e `/health/ready` do destino
    3. Resolvido o destino, reprocessar as sagas afetadas
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 0
  }

  tags = local.tags_fluxo
}

# ---------------------------------------------------------------------------
# Callback com 409 repetido: conflito de versao persistente na OS/saga.
# ---------------------------------------------------------------------------
resource "datadog_monitor" "callback_conflito_repetido" {
  count = local.habilitado ? 1 : 0

  name  = "[AVISO] Callbacks recebendo 409 repetidamente ({{type.name}})"
  type  = "query alert"
  query = "sum(last_15m):default_zero(sum:oficina.callbacks.count{resultado:conflito} by {type}.as_count()) > 3"

  message = <<-EOT
    {{value}} callbacks `{{type.name}}` responderam 409 nos ultimos 15 minutos.

    **O que significa:** o OS refez a transacao 3x e ainda houve conflito de versao
    — concorrencia anormal na mesma OS (callback duplicado em rajada, varredor de
    timeouts e callback ao mesmo tempo). O participante repete; se desistir, a saga para.

    **Runbook:** ${local.runbooks}/callback-conflito-repetido.md
    1. Logs `callback recebido` com `resultado:conflito` -> `correlation_id` das OS
    2. `GET /ordens-servico/numero/<n>/saga` para cada uma
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 3
    warning  = 1
  }

  tags = local.tags_fluxo
}

# ---------------------------------------------------------------------------
# Latencia p95 entre servicos > 2 s (inclui as retentativas do cliente do kit).
# ---------------------------------------------------------------------------
resource "datadog_monitor" "latencia_entre_servicos" {
  count = local.habilitado ? 1 : 0

  name  = "[AVISO] Latencia p95 entre servicos acima de 2 s ({{origem.name}} -> {{destino.name}})"
  type  = "query alert"
  query = "avg(last_10m):p95:oficina.http_interno_duracao_seconds{*} by {origem,destino} > ${local.limite_p95_interno}"

  message = <<-EOT
    p95 de {{origem.name}} -> {{destino.name}} em {{value}} s (limite ${local.limite_p95_interno} s).

    **O que significa:** o destino esta lento ou as chamadas estao precisando de
    retentativa (o timeout por tentativa e 5 s). A requisicao do usuario que
    disparou a saga fica lenta junto.

    **Runbook:** ${local.runbooks}/latencia-entre-servicos.md
    1. Dashboard "Oficina — Fluxo distribuído" -> p95 por par e chamadas por rota
    2. Trace no APM filtrando `correlation_id` de uma OS lenta
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = local.limite_p95_interno
    warning  = 1
  }

  tags = local.tags_fluxo
}

# ---------------------------------------------------------------------------
# 5xx por servico (os-service, billing-service, execucao-service): label `service`
# que o MetricsModule do kit poe em toda serie.
# ---------------------------------------------------------------------------
resource "datadog_monitor" "erros_5xx_por_servico" {
  count = local.habilitado ? 1 : 0

  name  = "[CRITICO] 5xx no {{service.name}}"
  type  = "query alert"
  query = "sum(last_10m):default_zero(sum:oficina.http_request_duration_seconds.count{status:5*} by {service}.as_count()) > 5"

  message = <<-EOT
    {{value}} respostas 5xx do {{service.name}} nos ultimos 10 minutos.

    **O que significa:** excecao nao tratada no servico. Quando o servico e
    destino de chamadas da saga, as chamadas do OS repetem e podem esgotar
    (ver "retry esgotado").

    **Runbook:** ${local.runbooks}/erros-5xx-por-servico.md
    1. Dashboard "Oficina — Fluxo distribuído" -> 5xx por servico; "Saude tecnica" -> 5xx por rota
    2. Logs do servico com `statusCode:5*` -> `correlation_id` / `trace_id`
    3. Banco do servico (`/health/ready`): RDS ou DynamoDB
    ${local.destino}
  EOT

  monitor_thresholds {
    critical = 5
    warning  = 2
  }

  tags = local.tags_fluxo
}
