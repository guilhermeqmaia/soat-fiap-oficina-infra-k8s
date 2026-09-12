#!/usr/bin/env bash
# Instala o coletor de observabilidade no EKS (US-F3-10) com os values
# versionados em observability/:
#   datadog     — primaria (ADR-0004); exige DD_API_KEY no ambiente
#   prometheus  — alternativa OSS (kube-prometheus-stack + Grafana), sem chave
#   none        — remove o que estiver instalado
#
# Uso: scripts/aws-observability.sh datadog|prometheus|none [--profile oficina]
# Pre-requisitos: helm, kubectl, aws (cluster ja no ar — aws-deploy-all.sh).
set -euo pipefail
MODE="${1:?datadog|prometheus|none}"; shift || true
PROFILE="oficina"; [ "${1:-}" = "--profile" ] && PROFILE="$2"
export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CLUSTER="${EKS_CLUSTER_NAME:-oficina-mecanica-eks}"
aws eks update-kubeconfig --name "$CLUSTER" >/dev/null

case "$MODE" in
  datadog)
    [ -n "${DD_API_KEY:-}" ] || { echo "erro: exporte DD_API_KEY (trial do Datadog)" >&2; exit 1; }
    helm repo add datadog https://helm.datadoghq.com >/dev/null 2>&1 || true; helm repo update >/dev/null
    kubectl get ns datadog >/dev/null 2>&1 || kubectl create ns datadog >/dev/null
    kubectl -n datadog create secret generic datadog-secret --from-literal=api-key="$DD_API_KEY" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    helm upgrade --install datadog datadog/datadog -n datadog -f "$HERE/observability/datadog-values.yaml" --wait --timeout 10m >/dev/null
    kubectl -n datadog get pods --no-headers | awk '{print "   "$1, $3}'
    echo "datadog instalado — traces/logs/metricas da app (DD_TRACE_ENABLED=true no overlay k8s-aws) chegam em https://app.datadoghq.com"
    ;;
  prometheus)
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true; helm repo update >/dev/null
    PASS="${GRAFANA_ADMIN_PASSWORD:-$(openssl rand -hex 8)}"
    helm upgrade --install obs prometheus-community/kube-prometheus-stack -n observability --create-namespace \
      -f "$HERE/observability/prometheus-values.yaml" --set grafana.adminPassword="$PASS" --wait --timeout 10m >/dev/null
    kubectl -n observability get pods --no-headers | awk '{print "   "$1, $3}'
    echo "prometheus+grafana instalados (retencao 7d). Acesso local:"
    echo "   kubectl -n observability port-forward svc/obs-grafana 3001:80   # http://localhost:3001  admin / $PASS"
    echo "   kubectl -n observability port-forward svc/obs-kube-prometheus-stack-prometheus 9090:9090"
    ;;
  none)
    helm uninstall datadog -n datadog >/dev/null 2>&1 && echo "   datadog removido" || true
    helm uninstall obs -n observability >/dev/null 2>&1 && echo "   prometheus removido" || true
    kubectl delete ns datadog observability --ignore-not-found >/dev/null; echo "observabilidade removida"
    ;;
  *) echo "modo invalido: $MODE" >&2; exit 1 ;;
esac
