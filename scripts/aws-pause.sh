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

echo "== node group $NODES -> 0"
aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NODES" \
  --scaling-config minSize=0,maxSize=4,desiredSize=0 >/dev/null
echo "== RDS $DB -> stop"
st=$(aws rds describe-db-instances --db-instance-identifier "$DB" --query 'DBInstances[0].DBInstanceStatus' --output text)
[ "$st" = available ] && aws rds stop-db-instance --db-instance-identifier "$DB" >/dev/null || echo "   (status atual: $st)"
echo "pausado. Retomar: scripts/aws-resume.sh"
