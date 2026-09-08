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

## Monitores sintéticos

[`synthetics.tf`](synthetics.tf) provisiona checks de uptime batendo no
**endpoint público do gateway**. Só é aplicado quando as chaves do Datadog
estão configuradas (`datadog_api_key`/`datadog_app_key`), então o stage
continua verde sem elas.
