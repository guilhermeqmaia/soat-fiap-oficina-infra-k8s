#!/usr/bin/env bash
# Sobe TODA a Fase 3 do zero disparando os workflows de CD dos 4 repos e
# fechando os contratos entre eles (outputs -> GitHub Variables). As etapas
# independentes rodam em paralelo:
#
#   cluster (VPC+EKS, ~16 min) ─┐
#   RDS (~14 min) -> Lambda (~3) ─┴─> app (~4) -> gateway (~3) -> app c/ URL (~3) -> seeds -> smoke
#
# O RDS e a Lambda so precisam da VPC/subnets/SGs, que o stage cluster cria nos
# primeiros ~2 min — o script le esses IDs direto da AWS (tags) sem esperar o
# EKS. O cd.yml da Lambda nao roda aqui: o Terraform ja publica a versao e o
# alias a acompanha; ele so faz sentido em push de codigo novo.
#
# Uso: scripts/aws-deploy-all.sh [--profile oficina] [--env prod] [--no-seed] [--from <etapa>]
#   --from cluster|db|lambda|app|gateway|url|seed   retoma a partir de uma etapa
# Pre-requisitos: aws, kubectl, gh (logado), python3, curl. Vars/secrets
# estaveis ja criados pelo aws-account-bootstrap.sh. Do zero: ~30 min.
set -euo pipefail

PROFILE="oficina"; ENV="prod"; SEED=true; FROM="cluster"
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift ;;
    --env) ENV="$2"; shift ;;
    --no-seed) SEED=false ;;
    --from) FROM="$2"; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 1 ;;
  esac; shift
done

OWNER="${GH_OWNER:-guilhermeqmaia}"
REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT_NAME:-oficina-mecanica}"
R_K8S="$OWNER/soat-fiap-oficina-infra-k8s"; R_DB="$OWNER/soat-fiap-oficina-infra-db"
R_LAMBDA="$OWNER/soat-fiap-oficina-auth-lambda"; R_APP="$OWNER/soat-fiap-oficina-mecanica-app"
export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="$REGION"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${TF_STATE_BUCKET:-soat-oficina-tfstate-$ACCOUNT}"
BRANCH="main"; [ "$ENV" = "prod" ] || BRANCH="homolog"
START=$(date +%s)
log() { printf '\n[%s +%dmin] %s\n' "$(date -u +%H:%M)" $(( ($(date +%s)-START)/60 )) "$*"; }
setvar() { gh variable set "$2" -R "$1" --body "$3" >/dev/null && echo "   $1 :: $2 = $3"; }
stages=(cluster db lambda app gateway url seed); idx() { local i=0; for s in "${stages[@]}"; do [ "$s" = "$1" ] && { echo $i; return; }; i=$((i+1)); done; echo 99; }
skip() { [ "$(idx "$1")" -lt "$(idx "$FROM")" ]; }

# dispatch_wf <repo> <workflow> [-f k=v ...]  -> imprime o id do run
dispatch_wf() {
  local repo="$1" wf="$2"; shift 2
  local before; before=$(gh run list -R "$repo" --workflow "$wf" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || echo 0)
  gh workflow run "$wf" -R "$repo" --ref "$BRANCH" "$@"
  local id=""
  for i in $(seq 1 20); do
    sleep 5
    id=$(gh run list -R "$repo" --workflow "$wf" --event workflow_dispatch --limit 1 --json databaseId -q '.[0].databaseId')
    [ -n "$id" ] && [ "$id" != "$before" ] && break; id=""
  done
  [ -n "$id" ] || { echo "erro: run de $wf em $repo nao apareceu" >&2; exit 1; }
  echo "   $repo :: $wf -> https://github.com/$repo/actions/runs/$id" >&2
  echo "$id"
}
# wait_wf <repo> <run-id>  -> falha com a URL se o run nao tiver sucesso
wait_wf() {
  local st
  while st=$(gh run view "$2" -R "$1" --json status,conclusion -q '"\(.status)/\(.conclusion)"'); [ "${st%%/*}" != "completed" ]; do sleep 30; done
  [ "${st#*/}" = "success" ] || { echo "erro: run $2 em $1 terminou com ${st#*/}: https://github.com/$1/actions/runs/$2" >&2; exit 1; }
}
run_wf() { local id; id=$(dispatch_wf "$@"); wait_wf "$1" "$id"; }
tf_out() { aws s3 cp "s3://$BUCKET/$1" - 2>/dev/null | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['outputs']['$2']['value']))"; }
# Espera um recurso com a tag Name existir (o stage cluster cria a rede antes do EKS).
wait_tag() { # wait_tag <describe-cmd> <Name> <min-count> <jmespath-ids>
  local n=0
  for i in $(seq 1 60); do
    n=$(aws ec2 "$1" --filters "Name=tag:Name,Values=$2" --query "length($4)" --output text 2>/dev/null || echo 0)
    [ "${n:-0}" -ge "$3" ] && { aws ec2 "$1" --filters "Name=tag:Name,Values=$2" --query "$4" --output json | tr -d ' \n'; return; }
    sleep 15
  done
  echo "erro: '$2' nao apareceu na AWS (esperava $3)" >&2; exit 1
}

echo "conta $ACCOUNT | env $ENV ($BRANCH) | state s3://$BUCKET | a partir de: $FROM"

# --- 1. Cluster: dispara e NAO espera --------------------------------------------
CLUSTER_RUN=""
if ! skip cluster; then
  log "1/7 cluster: VPC + EKS (~16 min, em paralelo com o banco)"
  gh variable delete AUTH_LAMBDA_ARN -R "$R_K8S" 2>/dev/null || true   # ARNs do ciclo anterior nao valem
  gh variable delete BACKEND_LISTENER_ARN -R "$R_K8S" 2>/dev/null || true
  CLUSTER_RUN=$(dispatch_wf "$R_K8S" cd.yml -f action=apply -f stage=cluster)
fi
log "rede: aguardando VPC/subnets/SGs do stage cluster"
VPC_ID=$(wait_tag describe-vpcs "$PROJECT-vpc" 1 'Vpcs[].VpcId' | tr -d '[]"')
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)
SUBNETS=$(wait_tag describe-subnets "$PROJECT-private-*" 2 'Subnets[].SubnetId')
VPC_LINK_SG=$(wait_tag describe-security-groups "$PROJECT-vpc-link" 1 'SecurityGroups[].GroupId' | tr -d '[]"')
LAMBDA_SG=$(wait_tag describe-security-groups "$PROJECT-auth-lambda" 1 'SecurityGroups[].GroupId' | tr -d '[]"')
CLUSTER="$PROJECT-eks"
log "contratos de rede"
setvar "$R_DB" VPC_ID "$VPC_ID"; setvar "$R_DB" DB_SUBNET_IDS "$SUBNETS"; setvar "$R_DB" DB_ALLOWED_CIDRS "[\"$VPC_CIDR\"]"
setvar "$R_LAMBDA" SUBNET_IDS "$SUBNETS"; setvar "$R_LAMBDA" SECURITY_GROUP_IDS "[\"$LAMBDA_SG\"]"
setvar "$R_K8S" VPC_LINK_SUBNET_IDS "$SUBNETS"; setvar "$R_K8S" VPC_LINK_SECURITY_GROUP_IDS "[\"$VPC_LINK_SG\"]"
setvar "$R_APP" EKS_CLUSTER_NAME "$CLUSTER"

# --- 2. RDS (enquanto o EKS sobe) -------------------------------------------------
if ! skip db; then
  log "2/7 infra-db: RDS Multi-AZ (~14 min)"
  run_wf "$R_DB" cd.yml -f action=apply
fi
DB_SECRET_ARN=$(tf_out "oficina-infra-db/$ENV.tfstate" secret_arn | tr -d '"'); DB_SECRET_NAME=$(tf_out "oficina-infra-db/$ENV.tfstate" secret_name | tr -d '"')
log "contratos do banco"
setvar "$R_LAMBDA" DB_SECRET_ID "$DB_SECRET_ARN"; setvar "$R_APP" DB_SECRET_ID "$DB_SECRET_NAME"

# --- 3. Lambda (Terraform ja publica versao + alias) -----------------------------
if ! skip lambda; then
  log "3/7 auth-lambda: Terraform (~3 min)"
  run_wf "$R_LAMBDA" infra.yml -f environment="$ENV" -f action=apply
fi
FN=$(tf_out "oficina-auth-lambda/$ENV.tfstate" function_name | tr -d '"'); JWT_SECRET_ARN=$(tf_out "oficina-auth-lambda/$ENV.tfstate" jwt_secret_arn | tr -d '"')
ALIAS_ARN=$(aws lambda get-alias --function-name "$FN" --name "$ENV" --query AliasArn --output text)
log "contratos da lambda"
setvar "$R_APP" JWT_SECRET_ID "$JWT_SECRET_ARN"; setvar "$R_K8S" AUTH_LAMBDA_ARN "$ALIAS_ARN"; setvar "$R_LAMBDA" LAMBDA_FUNCTION_NAME "$FN"

# --- 4. App no EKS (precisa do cluster pronto) ------------------------------------
if [ -n "$CLUSTER_RUN" ]; then log "aguardando o cluster terminar"; wait_wf "$R_K8S" "$CLUSTER_RUN"; fi
if ! skip app; then
  log "4/7 app: build + ECR + EKS + migrations (~4 min)"
  run_wf "$R_APP" cd-aws.yml
fi
aws eks update-kubeconfig --name "$CLUSTER" >/dev/null
NLB=$(kubectl -n oficina get svc oficina-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
LB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='$NLB'].LoadBalancerArn" --output text)
LISTENER=$(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" --query 'Listeners[0].ListenerArn' --output text)
log "contrato do backend"; setvar "$R_K8S" BACKEND_LISTENER_ARN "$LISTENER"

# --- 5. Gateway (so o stage gateway) ----------------------------------------------
if ! skip gateway; then
  log "5/7 gateway: API Gateway + VPC Link (~3 min)"
  run_wf "$R_K8S" cd.yml -f action=apply -f stage=gateway
fi
GW=$(tf_out "oficina-infra-k8s/gateway/$ENV.tfstate" api_base_url | tr -d '"')
log "URL publica: $GW"; setvar "$R_APP" GATEWAY_URL "$GW"

# --- 6. App de novo, com a URL publica (links de aprovacao, CORS) -----------------
if ! skip url; then
  log "6/7 app: redeploy com GATEWAY_URL (~3 min)"
  run_wf "$R_APP" cd-aws.yml
fi

# --- 7. Seeds + smoke -------------------------------------------------------------
if $SEED && ! skip seed; then
  log "7/7 seeds de teste (clientes, catalogo, usuarios staff)"
  kubectl -n oficina exec deploy/oficina-app -c app -- sh -c \
    'for f in prisma/seeds/01_test_data.sql prisma/seeds/03_test_users.sql; do npx prisma db execute --file $f; done' 2>&1 | grep -v -E "Defaulted|Update available|^[│┌└─ ]*$" || true
fi
log "smoke test pelo gateway"
ok=true
for i in 1 2 3 4 5 6; do c=$(curl -s -o /dev/null -w '%{http_code}' "$GW/health"); [ "$c" = 200 ] && break; sleep 10; done
printf '   GET /health -> %s\n' "$c"; [ "$c" = 200 ] || ok=false
c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/auth" -H 'content-type: application/json' -d '{"cpf":"11111111111"}'); printf '   POST /auth cpf invalido -> %s (esperado 422)\n' "$c"; [ "$c" = 422 ] || ok=false
c=$(curl -s -o /dev/null -w '%{http_code}' "$GW/clientes"); printf '   GET /clientes sem token -> %s (esperado 401)\n' "$c"; [ "$c" = 401 ] || ok=false
if $SEED; then
  c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GW/auth" -H 'content-type: application/json' -d '{"cpf":"52998224725","senha":"admin123"}'); printf '   POST /auth admin -> %s (esperado 200)\n' "$c"; [ "$c" = 200 ] || ok=false
fi
$ok || { echo "smoke test FALHOU" >&2; exit 1; }
log "PRONTO em $(( ($(date +%s)-START)/60 )) min — $GW"
$SEED && echo "   demo: admin CPF 52998224725 / admin123 · cliente CPF 39053344705 · mecanico CPF 16899535009 / mecanico123"
echo "   pausar entre gravacoes: scripts/aws-pause.sh · retomar: scripts/aws-resume.sh · derrubar: scripts/aws-destroy-all.sh --yes"
