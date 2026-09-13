#!/usr/bin/env bash
# Derruba TODA a infra da Fase 3 na ordem inversa do deploy, para nao seguir
# cobrando fora dos dias de demo. Roda localmente com o profile de admin e o
# MESMO state remoto do CI (S3), pois a ordem entre os repos importa:
#
#   app (namespace -> NLB)  ->  gateway  ->  auth-lambda  ->  infra-db  ->  cluster
#
# Uso: scripts/aws-destroy-all.sh [--profile oficina] [--env prod] [--yes]
# Pre-requisitos: aws, terraform, kubectl, gh (logado), git, node/npm.
# Le as GitHub Variables dos repos para preencher as variaveis do Terraform
# (mesmos valores do CI). Clona os outros repos em diretorio temporario.
set -euo pipefail

PROFILE="oficina"; ENV="prod"; YES=false
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift ;;
    --env) ENV="$2"; shift ;;
    --yes) YES=true ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 1 ;;
  esac; shift
done

OWNER="${GH_OWNER:-guilhermeqmaia}"
REGION="${AWS_REGION:-us-east-1}"
export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="$REGION" TF_IN_AUTOMATION=1 TF_INPUT=0
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${TF_STATE_BUCKET:-soat-oficina-tfstate-$ACCOUNT}"
LOCK_TABLE="${TF_STATE_LOCK_TABLE:-soat-oficina-tflock}"
CLUSTER="${EKS_CLUSTER_NAME:-oficina-mecanica-eks}"
WORK="$(mktemp -d /tmp/oficina-destroy.XXXX)"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ghvar() { gh variable get "$2" -R "$OWNER/$1" 2>/dev/null || true; }

echo "conta $ACCOUNT | env $ENV | state s3://$BUCKET | cluster $CLUSTER"
$YES || { read -r -p "Destruir TUDO? (digite 'destroy') " a; [ "$a" = destroy ] || exit 1; }

tf_init() { # tf_init <dir> <state-key> [lock]
  ( cd "$1"
    grep -qs 'backend "s3"' ./*.tf || printf 'terraform {\n  backend "s3" {}\n}\n' > backend_override.tf
    terraform init -input=false -reconfigure \
      -backend-config="bucket=$BUCKET" -backend-config="key=$2" \
      -backend-config="region=$REGION" -backend-config="encrypt=true" \
      ${3:+-backend-config="dynamodb_table=$LOCK_TABLE"} >/dev/null )
}
tf_has_state() { ( cd "$1" && [ -n "$(terraform state list 2>/dev/null)" ] ); }

# --- 0. Observabilidade (agente + dashboards/monitores no Datadog) ------------
"$HERE/scripts/aws-observability.sh" none --profile "$PROFILE" || true

# --- 1. App: namespace inteiro (NLB interno + ENIs, pods, HPA) --------------
if aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1; then
  echo "== app: removendo namespace oficina"
  aws eks update-kubeconfig --name "$CLUSTER" >/dev/null
  kubectl delete namespace oficina --ignore-not-found --timeout=300s || true
  for i in $(seq 1 24); do
    n=$(aws elbv2 describe-load-balancers --query 'length(LoadBalancers)' --output text)
    [ "$n" = "0" ] && break; echo "   aguardando NLB sumir ($n)..."; sleep 10
  done
fi

# --- 2. Gateway ---------------------------------------------------------------
echo "== gateway"
tf_init "$HERE/gateway" "oficina-infra-k8s/gateway/$ENV.tfstate"
if tf_has_state "$HERE/gateway"; then
  ( cd "$HERE/gateway" && terraform destroy -auto-approve \
      -var "auth_lambda_arn=$(ghvar soat-fiap-oficina-infra-k8s AUTH_LAMBDA_ARN)" \
      -var "backend_listener_arn=$(ghvar soat-fiap-oficina-infra-k8s BACKEND_LISTENER_ARN)" \
      -var "vpc_link_subnet_ids=$(ghvar soat-fiap-oficina-infra-k8s VPC_LINK_SUBNET_IDS)" \
      -var "vpc_link_security_group_ids=$(ghvar soat-fiap-oficina-infra-k8s VPC_LINK_SECURITY_GROUP_IDS)" )
else echo "   state vazio"; fi

# --- 3. Lambda de auth --------------------------------------------------------
echo "== auth-lambda"
git clone -q "https://github.com/$OWNER/soat-fiap-oficina-auth-lambda" "$WORK/lambda"
( cd "$WORK/lambda" && npm ci --silent >/dev/null 2>&1 && npm run package --silent >/dev/null 2>&1 ) # lambda.zip: filebase64sha256 e avaliado ate no destroy
tf_init "$WORK/lambda/infra/terraform" "oficina-auth-lambda/$ENV.tfstate"
if tf_has_state "$WORK/lambda/infra/terraform"; then
  ( cd "$WORK/lambda/infra/terraform" && terraform destroy -auto-approve \
      -var "environment=$ENV" -var "jwt_secret_value=$(printf 'x%.0s' $(seq 1 40))" -var "database_url=postgresql://x" \
      -var "subnet_ids=$(ghvar soat-fiap-oficina-auth-lambda SUBNET_IDS)" \
      -var "security_group_ids=$(ghvar soat-fiap-oficina-auth-lambda SECURITY_GROUP_IDS)" \
      -var "db_secret_id=$(ghvar soat-fiap-oficina-auth-lambda DB_SECRET_ID)" )
else echo "   state vazio"; fi

# --- 4. RDS: em prod deletion_protection=true — desliga e depois destroi ----
echo "== infra-db"
git clone -q "https://github.com/$OWNER/soat-fiap-oficina-infra-db" "$WORK/db"
tf_init "$WORK/db" "oficina-infra-db/$ENV.tfstate" lock
if tf_has_state "$WORK/db"; then
  dbvars=(-var "environment=$ENV"
          -var "vpc_id=$(ghvar soat-fiap-oficina-infra-db VPC_ID)"
          -var "subnet_ids=$(ghvar soat-fiap-oficina-infra-db DB_SUBNET_IDS)"
          -var "allowed_cidr_blocks=$(ghvar soat-fiap-oficina-infra-db DB_ALLOWED_CIDRS)"
          -var "backup_retention_period=$(ghvar soat-fiap-oficina-infra-db DB_BACKUP_RETENTION_DAYS)"
          -var deletion_protection=false -var skip_final_snapshot=true -var apply_immediately=true)
  ( cd "$WORK/db" && terraform apply -auto-approve "${dbvars[@]}" && terraform destroy -auto-approve "${dbvars[@]}" )
else echo "   state vazio"; fi

# --- 5. Cluster (VPC, NAT, EKS, roles) ----------------------------------------
echo "== cluster"
# ENIs da Lambda (Hyperplane) demoram ate ~20 min para a AWS liberar apos o
# destroy da function; as ja desanexadas podem ser apagadas na hora. Sem isso
# o destroy do SG da Lambda (stage cluster) fica preso em DependencyViolation.
for sg in $(aws ec2 describe-security-groups --filters Name=tag:Name,Values=oficina-mecanica-auth-lambda --query 'SecurityGroups[].GroupId' --output text); do
  for i in $(seq 1 60); do
    for eni in $(aws ec2 describe-network-interfaces --filters Name=group-id,Values="$sg" Name=status,Values=available --query 'NetworkInterfaces[].NetworkInterfaceId' --output text); do
      aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null && echo "   eni $eni apagada" || true
    done
    n=$(aws ec2 describe-network-interfaces --filters Name=group-id,Values="$sg" --query 'length(NetworkInterfaces)' --output text)
    [ "$n" = "0" ] && break; echo "   aguardando ENIs da Lambda ($n)..."; sleep 20
  done
done
tf_init "$HERE/cluster" "oficina-infra-k8s/cluster/$ENV.tfstate"
if tf_has_state "$HERE/cluster"; then
  ( cd "$HERE/cluster" && terraform destroy -auto-approve \
      -var "cluster_admin_arns=$(ghvar soat-fiap-oficina-infra-k8s CLUSTER_ADMIN_ARNS)" \
      -var "node_instance_types=$(ghvar soat-fiap-oficina-infra-k8s NODE_INSTANCE_TYPES)" )
else echo "   state vazio"; fi

# --- 6. Restos fora do Terraform ---------------------------------------------
echo "== ecr"; for r in $(aws ecr describe-repositories --query 'repositories[].repositoryName' --output text); do
  aws ecr delete-repository --repository-name "$r" --force >/dev/null && echo "   $r"; done
echo "== secrets manager (inclui os ja agendados: sem --include-planned-deletion o list nao os mostra)"
for s in $(aws secretsmanager list-secrets --include-planned-deletion --query 'SecretList[].ARN' --output text); do
  aws secretsmanager delete-secret --secret-id "$s" --force-delete-without-recovery >/dev/null && echo "   $s"; done
echo "== cloudwatch log groups"; for g in $(aws logs describe-log-groups --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$g" && echo "   $g"; done
rm -rf "$WORK" "$HERE"/*/backend_override.tf
echo "pronto. Ficam so: bucket do state, tabela de lock, role OIDC e budget (custo ~0)."
echo "Sobras cobraveis? (tudo deve ser 0):"
for q in "ec2 describe-network-interfaces --query length(NetworkInterfaces)" "ec2 describe-nat-gateways --filter Name=state,Values=available --query length(NatGateways)" "ec2 describe-addresses --query length(Addresses)" "elbv2 describe-load-balancers --query length(LoadBalancers)" "rds describe-db-instances --query length(DBInstances)" "eks list-clusters --query length(clusters)" "ec2 describe-volumes --query length(Volumes)"; do
  printf '   %-45s %s\n' "$(echo "$q" | cut -d' ' -f1-2)" "$(aws $q --output text)"; done
