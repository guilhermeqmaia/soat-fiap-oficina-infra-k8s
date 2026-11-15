#!/usr/bin/env bash
# Retoma o ambiente pausado por scripts/aws-pause.sh: liga o RDS, volta o node
# group para 2 instancias, espera pods e NLB e roda o smoke test pelo gateway.
#
# Uso: scripts/aws-resume.sh [--profile oficina]
set -euo pipefail
PROFILE="oficina"; [ "${1:-}" = "--profile" ] && PROFILE="$2"
export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
OWNER="${GH_OWNER:-guilhermeqmaia}"
PROJECT="${PROJECT_NAME:-oficina-mecanica}"; CLUSTER="$PROJECT-eks"; NODES="$PROJECT-nodes"; DB="$PROJECT-prod"
APPS="oficina-app oficina-billing-service oficina-execucao-service"; DBS="$DB $DB-billing"
START=$(date +%s); log() { printf '[%s +%dmin] %s\n' "$(date -u +%H:%M)" $(( ($(date +%s)-START)/60 )) "$*"; }

log "RDS ($DBS) -> start (o mais lento, ~5-8 min) e node group -> 2 (em paralelo)"
for db in $DBS; do
  st=$(aws rds describe-db-instances --db-instance-identifier "$db" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo inexistente)
  [ "$st" = stopped ] && aws rds start-db-instance --db-instance-identifier "$db" >/dev/null || echo "   ($db status: $st)"
done
aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NODES" \
  --scaling-config minSize=2,maxSize=4,desiredSize=2 >/dev/null
aws eks update-kubeconfig --name "$CLUSTER" >/dev/null
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ')" -ge 2 ]; do sleep 15; done
log "2 nodes Ready"
for db in $DBS; do
  aws rds describe-db-instances --db-instance-identifier "$db" >/dev/null 2>&1 && aws rds wait db-instance-available --db-instance-identifier "$db"
done
log "RDS available"
for app in $APPS; do
  kubectl -n oficina get deployment "$app" >/dev/null 2>&1 || continue
  kubectl -n oficina scale deployment/"$app" --replicas=2  # o HPA assume a partir daqui (min 2)
done
for app in $APPS; do
  kubectl -n oficina get deployment "$app" >/dev/null 2>&1 && kubectl -n oficina rollout status deployment/"$app" --timeout=300s
done
log "servicos prontos"
# Fase 4: NodePort atras do NLB unico do stage gateway (ADR-0013); o health check
# do target group leva ~1 min para marcar os nodes como saudaveis.
GW=$(gh variable get GATEWAY_URL -R "$OWNER/soat-fiap-oficina-os-service")
for i in $(seq 1 30); do c=$(curl -s -o /dev/null -w '%{http_code}' "$GW/health"); [ "$c" = 200 ] && break; sleep 10; done
c2=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/auth" -H 'content-type: application/json' -d '{"cpf":"52998224725","senha":"admin123"}')
log "smoke: GET /health -> $c · POST /auth admin -> $c2"
[ "$c" = 200 ] && [ "$c2" = 200 ] && log "PRONTO em $(( ($(date +%s)-START)/60 )) min — $GW" || { echo "smoke FALHOU" >&2; exit 1; }
