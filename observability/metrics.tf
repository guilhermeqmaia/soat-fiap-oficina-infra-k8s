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
