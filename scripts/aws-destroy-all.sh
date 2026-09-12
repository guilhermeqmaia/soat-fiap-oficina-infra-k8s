#!/usr/bin/env bash
# Derruba TODA a infra da Fase 3 na ordem inversa do deploy, para nao seguir
# cobrando fora dos dias de demo. Roda localmente com o profile de admin
# (state remoto em S3 — o mesmo do CI), pois a ordem entre repos importa:
#
#   app (NLB via Service)  ->  gateway  ->  auth-lambda  ->  infra-db  ->  cluster
#
# Uso: scripts/aws-destroy-all.sh [--profile oficina] [--env prod] [--yes]
# Pre-requisitos: aws, terraform, kubectl, gh, git. Clona os outros repos em
# um diretorio temporario (nao mexe nos seus checkouts).
set -euo pipefail

PROFILE="oficina"; ENV="prod"; YES=false
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift ;;
    --env) ENV="$2"; shift ;;
    --yes) YES=true ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 1 ;;
  esac; shift
done

OWNER="${GH_OWNER:-guilhermeqmaia}"
REGION="${AWS_REGION:-us-east-1}"
export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="$REGION" TF_IN_AUTOMATION=1
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${TF_STATE_BUCKET:-soat-oficina-tfstate-$ACCOUNT}"
LOCK_TABLE="${TF_STATE_LOCK_TABLE:-soat-oficina-tflock}"
CLUSTER="${EKS_CLUSTER_NAME:-oficina-mecanica-eks}"
WORK="$(mktemp -d /tmp/oficina-destroy.XXXX)"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo "conta $ACCOUNT | env $ENV | state s3://$BUCKET | cluster $CLUSTER"
$YES || { read -r -p "Destruir TUDO? (digite 'destroy') " a; [ "$a" = destroy ] || exit 1; }

tf_destroy() { # tf_destroy <dir> <state-key> [args...]
  local dir="$1" key="$2"; shift 2
  echo "== terraform destroy: $dir ($key)"
  ( cd "$dir"
    [ -f versions.tf ] && grep -q 'backend "s3"' versions.tf backend.tf 2>/dev/null \
      || printf 'terraform {\n  backend "s3" {}\n}\n' > backend_override.tf
    terraform init -input=false -reconfigure \
      -backend-config="bucket=$BUCKET" -backend-config="key=$key" \
      -backend-config="region=$REGION" -backend-config="encrypt=true" \
      ${LOCK:+-backend-config="dynamodb_table=$LOCK_TABLE"} >/dev/null
    if ! terraform state list >/dev/null 2>&1 || [ -z "$(terraform state list 2>/dev/null)" ]; then
      echo "   state vazio — nada a destruir"; return 0
    fi
    terraform destroy -input=false -auto-approve "$@" )
}

# --- 1. App: remover o Service tipo LoadBalancer (NLB interno + ENIs) -------
if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  echo "== app: removendo namespace oficina (NLB, pods, HPA)"
  aws eks update-kubeconfig --name "$CLUSTER" >/dev/null
  kubectl delete namespace oficina --ignore-not-found --timeout=300s || true
  for i in $(seq 1 20); do
    n=$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId!=null])" --output text)
    [ "$n" = "0" ] && break; echo "   aguardando NLB sumir ($n)..."; sleep 15
  done
fi

# --- 2. Gateway ------------------------------------------------------------
tf_destroy "$HERE/gateway" "oficina-infra-k8s/gateway/$ENV.tfstate" \
  -var "auth_lambda_arn=arn:aws:lambda:$REGION:$ACCOUNT:function:x" \
  -var "backend_listener_arn=arn:aws:elasticloadbalancing:$REGION:$ACCOUNT:listener/net/x/1/2" \
  -var 'vpc_link_subnet_ids=["subnet-x","subnet-y"]' -var 'vpc_link_security_group_ids=["sg-x"]'

# --- 3. Lambda de auth (ENIs na VPC demoram alguns minutos para liberar) ---
git clone -q "https://github.com/$OWNER/soat-fiap-oficina-auth-lambda" "$WORK/lambda"
( cd "$WORK/lambda" && npm ci --silent && npm run package --silent ) >/dev/null 2>&1 || true
tf_destroy "$WORK/lambda/infra/terraform" "oficina-auth-lambda/$ENV.tfstate" \
  -var "environment=$ENV" -var jwt_secret_value=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -var database_url=postgresql://x

# --- 4. RDS: em prod deletion_protection=true — desliga antes de destruir ---
git clone -q "https://github.com/$OWNER/soat-fiap-oficina-infra-db" "$WORK/db"
LOCK=1
( cd "$WORK/db"
  terraform init -input=false -reconfigure \
    -backend-config="bucket=$BUCKET" -backend-config="key=oficina-infra-db/$ENV.tfstate" \
    -backend-config="region=$REGION" -backend-config="encrypt=true" \
    -backend-config="dynamodb_table=$LOCK_TABLE" >/dev/null
  if [ -n "$(terraform state list 2>/dev/null)" ]; then
    vpc=$(terraform output -raw db_security_group_id >/dev/null 2>&1 && terraform state show aws_security_group.rds | sed -n 's/.*vpc_id *= *"\(.*\)"/\1/p' || echo vpc-x)
    subs=$(terraform state show aws_db_subnet_group.this | sed -n '/subnet_ids/,/]/p' | grep -o 'subnet-[a-z0-9]*' | sed 's/.*/"&"/' | paste -sd, -)
    common=(-var "environment=$ENV" -var "vpc_id=$vpc" -var "subnet_ids=[${subs:-\"subnet-x\",\"subnet-y\"}]")
    echo "== rds: desligando deletion_protection"
    terraform apply -input=false -auto-approve "${common[@]}" \
      -var deletion_protection=false -var skip_final_snapshot=true -var apply_immediately=true
    echo "== terraform destroy: rds"
    terraform destroy -input=false -auto-approve "${common[@]}" \
      -var deletion_protection=false -var skip_final_snapshot=true
  else echo "   state do rds vazio — nada a destruir"; fi )
unset LOCK

# --- 5. Cluster (VPC, NAT, EKS, roles) --------------------------------------
# SG da Lambda foi criado por CLI (fora do Terraform) — sai antes da VPC.
for sg in $(aws ec2 describe-security-groups --filters Name=group-name,Values=oficina-mecanica-auth-lambda --query 'SecurityGroups[].GroupId' --output text); do
  aws ec2 delete-security-group --group-id "$sg" && echo "   sg lambda $sg removido"
done
tf_destroy "$HERE/cluster" "oficina-infra-k8s/cluster/$ENV.tfstate"

# --- 6. Restos que nao sao do Terraform ------------------------------------
echo "== ecr: apagando imagens"
for r in $(aws ecr describe-repositories --query 'repositories[].repositoryName' --output text); do
  aws ecr delete-repository --repository-name "$r" --force >/dev/null && echo "   $r"
done
echo "== secrets manager: apagando sem janela de recuperacao"
for s in $(aws secretsmanager list-secrets --query 'SecretList[].ARN' --output text); do
  aws secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery >/dev/null && echo "   $s"
done
echo "== cloudwatch: log groups restantes"
for g in $(aws logs describe-log-groups --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$g" && echo "   $g"
done
rm -rf "$WORK"
echo "pronto. Ficam so: bucket do state, tabela de lock, role OIDC e budget (custo ~0)."
echo "Confira em 10 min: aws ec2 describe-network-interfaces --query 'length(NetworkInterfaces)' (deve ser 0)."
