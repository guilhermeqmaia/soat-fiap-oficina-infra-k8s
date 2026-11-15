# Percentis (p50/p95/p99) em metricas de distribuicao precisam ser habilitados
# (so para a latencia HTTP: o tempo por status usa media = sum/count, pois a
# distribuicao so passa a existir depois da primeira amostra real).
# POR metrica no Datadog (Metrics Summary > Advanced), senao consultas `p95:`
# falham com "missing_aggregation". Como codigo, para nao depender de clique.
resource "datadog_metric_tag_configuration" "latencia" {
  count = local.habilitado ? 1 : 0

  metric_name         = "oficina.http_request_duration_seconds"
  metric_type         = "distribution"
  include_percentiles = true
  tags                = ["route", "method", "status", "kube_namespace", "pod_name"]
}

# p95 entre servicos (US-F4-16): painel "Latencia p95 por par origem -> destino"
# e monitor latencia_entre_servicos.
# A metrica so existe no Datadog depois da primeira OS que atravessa os servicos:
# num ambiente recem-criado o Datadog recusa ("Cannot configure tags on a metric that
# does not exist"). O aws-observability.sh tenta com percentis e, se for esse o erro,
# aplica o resto sem eles; depois da primeira OS, rode o script de novo.
variable "percentis_http_interno" {
  description = "Habilita os percentis da latencia entre servicos (exige que a metrica ja exista no Datadog)."
  type        = bool
  default     = true
}

resource "datadog_metric_tag_configuration" "latencia_http_interno" {
  count = local.habilitado && var.percentis_http_interno ? 1 : 0

  metric_name         = "oficina.http_interno_duracao_seconds"
  metric_type         = "distribution"
  include_percentiles = true
  tags                = ["origem", "destino", "rota", "status", "service", "kube_namespace"]
}
