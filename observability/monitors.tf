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
