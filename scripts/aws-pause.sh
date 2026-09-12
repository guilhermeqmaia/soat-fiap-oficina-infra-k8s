#!/usr/bin/env bash
# "Pausa" o ambiente entre gravacoes sem destruir: node group -> 0 instancias e
# RDS parado (a AWS religa sozinha apos 7 dias). Continuam cobrando so o
# control plane do EKS (~US$ 2,40/dia) e o NAT (~US$ 1,10/dia). Retomar leva
# ~8-10 min (scripts/aws-resume.sh) em vez dos ~30 min do deploy do zero.
#
# Uso: scripts/aws-pause.sh [--profile oficina]
set -euo pipefail
PROFILE="oficina"; [ "${1:-}" = "--profile" ] && PROFILE="$2"
export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT_NAME:-oficina-mecanica}"; CLUSTER="$PROJECT-eks"; NODES="$PROJECT-nodes"; DB="$PROJECT-prod"

# Primeiro a app -> 0: com o RDS parado os pods ficam 0/1 e o PDB (minAvailable 1)
# passa a bloquear o drain dos nos. Com replicas=0 o HPA nao reescala.
echo "== app -> 0 replicas"
aws eks update-kubeconfig --name "$CLUSTER" >/dev/null
kubectl -n oficina scale deployment/oficina-app --replicas=0
kubectl -n oficina wait --for=delete pod -l app.kubernetes.io/name=oficina-app --timeout=120s 2>/dev/null || true
echo "== node group $NODES -> 0"
aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NODES" \
  --scaling-config minSize=0,maxSize=4,desiredSize=0 >/dev/null
echo "== RDS $DB -> stop"
st=$(aws rds describe-db-instances --db-instance-identifier "$DB" --query 'DBInstances[0].DBInstanceStatus' --output text)
[ "$st" = available ] && aws rds stop-db-instance --db-instance-identifier "$DB" >/dev/null || echo "   (status atual: $st)"
echo "pausado. Retomar: scripts/aws-resume.sh"
