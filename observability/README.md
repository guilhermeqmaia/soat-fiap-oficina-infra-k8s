# Observabilidade no cluster (US-F3-10)

Coletores que rodam **no EKS**; a instrumentação da aplicação (traces,
`/metrics`, métricas de negócio) vive no repo
[soat-fiap-oficina-mecanica-app](https://github.com/guilhermeqmaia/soat-fiap-oficina-mecanica-app).

## Sinais exigidos e onde cada um nasce

| Sinal | Origem |
|---|---|
| **Latência das APIs** (p50/p95/p99 por rota) | `oficina_http_request_duration_seconds` no `/metrics` da app |
| **CPU/memória por pod e node** | `kube-state-metrics` + node-exporter (agente) |
| **Healthcheck / uptime** | monitores sintéticos em `/health` e `/health/ready` (via gateway) — [`synthetics.tf`](synthetics.tf) |
| **Métricas do API Gateway** (latência de borda, 4xx/5xx, throttling) | access logs JSON no CloudWatch (stage `gateway/`) → forwarder |
| **Volume de OS e tempo por status** | `oficina_os_transicoes_total`, `oficina_os_tempo_no_status_seconds` |
| **Erros de integração** | `oficina_integracoes_total{integracao,resultado}` |
| **Logs correlacionados a traces** | `logInjection` do dd-trace + `x-correlation-id` (US-F3-09) |

## Instalação (Datadog — primária, ADR-0004)

```bash
helm repo add datadog https://helm.datadoghq.com && helm repo update
kubectl create namespace datadog
kubectl -n datadog create secret generic datadog-secret --from-literal=api-key="$DD_API_KEY"
helm upgrade --install datadog datadog/datadog -n datadog -f observability/datadog-values.yaml
```

A aplicação passa a enviar traces com `DD_TRACE_ENABLED=true` (+ `DD_ENV`,
`DD_SERVICE`, `DD_VERSION`) no ConfigMap do overlay `k8s-aws/`.

> **Sem IRSA:** o AWS Academy não permite criar OIDC provider, então a API key
> vem de um **Secret do cluster**, não de uma role.

## Alternativa OSS (se o trial expirar)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install obs prometheus-community/kube-prometheus-stack \
  -n observability --create-namespace -f observability/prometheus-values.yaml
```

Os sinais são os mesmos: a app expõe `/metrics` em **OpenMetrics**, consumido
tanto pelo agente do Datadog (`prometheusScrape`) quanto pelo Prometheus.

## Custo e retenção

Trial do Datadog: 14 dias, cobre a janela da demo/vídeo. Retenção padrão do
trial — métricas 15 meses, logs 15 dias, traces 15 dias. O
`kube-prometheus-stack` usa retenção de **7 dias** (`prometheus-values.yaml`),
suficiente para o período de avaliação e sem custo.

## Dashboards e alertas (US-F3-11)

Versionados como código em [`dashboards.tf`](dashboards.tf) e
[`monitors.tf`](monitors.tf) — aplicados junto com o resto do stage.

### Dashboards

| Painel | Conteúdo | Exigido por |
|---|---|---|
| **Oficina — Operação (negócio)** | volume diário de OS por status · tempo médio por status (p50/p95) · erros de integração · taxa de sucesso das integrações | enunciado |
| **Oficina — Saúde técnica** | latência p95/p99 por rota (com marcador do SLO) · taxa de 5xx · CPU/memória dos pods · réplicas (efeito do HPA) · latência e erros do API Gateway | US-F3-10 |

As URLs saem nos outputs `dashboard_negocio_url` / `dashboard_tecnico_url` —
é o que se abre na análise ao vivo do vídeo (US-F3-12).

### Alertas

| Alerta | Dispara quando | Severidade |
|---|---|---|
| **Falha no processamento de OS** | > 5 respostas 5xx em rotas `/ordens-servico` em 15 min | crítico |
| Falhas na entrega de notificações | > 3 falhas de webhook em 30 min | aviso |
| Latência acima do SLO | p95 > 500 ms por 10 min | aviso |
| CPU dos pods > 85% | 10 min | aviso |
| Pods em CrashLoopBackOff | > 5 restarts em 10 min | crítico |
| API pública fora do ar | monitor sintético de `/health` falhando | crítico |

Cada monitor traz na mensagem **o que significa** e um **runbook** de 2–3
passos — o alerta chega acionável, não como um "algo quebrou". O canal de
notificação é a var `alert_email` (vira `@email` na mensagem do Datadog);
para Slack, use `@slack-<canal>` com a integração instalada.

## Monitores sintéticos

[`synthetics.tf`](synthetics.tf) provisiona checks de uptime batendo no
**endpoint público do gateway**. Só é aplicado quando as chaves do Datadog
estão configuradas (`datadog_api_key`/`datadog_app_key`), então o stage
continua verde sem elas.
