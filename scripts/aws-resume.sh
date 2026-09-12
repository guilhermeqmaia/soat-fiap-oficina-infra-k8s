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
START=$(date +%s); log() { printf '[%s +%dmin] %s\n' "$(date -u +%H:%M)" $(( ($(date +%s)-START)/60 )) "$*"; }

log "RDS $DB -> start (o mais lento, ~5-8 min) e node group -> 2 (em paralelo)"
st=$(aws rds describe-db-instances --db-instance-identifier "$DB" --query 'DBInstances[0].DBInstanceStatus' --output text)
[ "$st" = stopped ] && aws rds start-db-instance --db-instance-identifier "$DB" >/dev/null || echo "   (RDS status: $st)"
aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NODES" \
  --scaling-config minSize=2,maxSize=4,desiredSize=2 >/dev/null
aws eks update-kubeconfig --name "$CLUSTER" >/dev/null
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ')" -ge 2 ]; do sleep 15; done
log "2 nodes Ready"
aws rds wait db-instance-available --db-instance-identifier "$DB"
log "RDS available"
kubectl -n oficina scale deployment/oficina-app --replicas=2  # o HPA assume a partir daqui (min 2)
kubectl -n oficina rollout status deployment/oficina-app --timeout=300s
NLB=$(kubectl -n oficina get svc oficina-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
LB=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='$NLB'].LoadBalancerArn" --output text)
TG=$(aws elbv2 describe-target-groups --load-balancer-arn "$LB" --query 'TargetGroups[0].TargetGroupArn' --output text)
until [ "$(aws elbv2 describe-target-health --target-group-arn "$TG" --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)" -ge 1 ]; do sleep 15; done
log "NLB com alvo saudavel"
GW=$(gh variable get GATEWAY_URL -R "$OWNER/soat-fiap-oficina-mecanica-app")
for i in $(seq 1 12); do c=$(curl -s -o /dev/null -w '%{http_code}' "$GW/health"); [ "$c" = 200 ] && break; sleep 10; done
c2=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/auth" -H 'content-type: application/json' -d '{"cpf":"52998224725","senha":"admin123"}')
log "smoke: GET /health -> $c · POST /auth admin -> $c2"
[ "$c" = 200 ] && [ "$c2" = 200 ] && log "PRONTO em $(( ($(date +%s)-START)/60 )) min — $GW" || { echo "smoke FALHOU" >&2; exit 1; }
