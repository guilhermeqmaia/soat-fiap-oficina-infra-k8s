#!/usr/bin/env bash
# Sobe TODA a Fase 3 do zero, na ordem certa, disparando os workflows de CD dos
# 4 repos e fechando os contratos entre eles (outputs -> GitHub Variables):
#
#   cluster (VPC/EKS) -> infra-db (RDS) -> auth-lambda (infra + codigo)
#     -> app (ECR/EKS, NLB) -> gateway (API Gateway) -> app de novo (URL publica)
#     -> seeds de teste -> smoke test pelo gateway
#
# Uso: scripts/aws-deploy-all.sh [--profile oficina] [--env prod] [--no-seed] [--from <etapa>]
#   --from cluster|db|lambda|app|gateway|url|seed   retoma a partir de uma etapa
# Pre-requisitos: aws, kubectl, gh (logado), python3. Vars/secrets estaveis ja
# criados pelo aws-account-bootstrap.sh. Tempo total: ~50 min (EKS e RDS).
set -euo pipefail

PROFILE="oficina"; ENV="prod"; SEED=true; FROM="cluster"
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift ;;
    --env) ENV="$2"; shift ;;
    --no-seed) SEED=false ;;
    --from) FROM="$2"; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 1 ;;
  esac; shift
done

OWNER="${GH_OWNER:-guilhermeqmaia}"
REGION="${AWS_REGION:-us-east-1}"
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

# Dispara um workflow e espera terminar; falha com a URL do run.
run_wf() { # run_wf <repo> <workflow> [-f k=v ...]
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
  echo "   $repo :: $wf -> https://github.com/$repo/actions/runs/$id"
  local st
  while st=$(gh run view "$id" -R "$repo" --json status,conclusion -q '"\(.status)/\(.conclusion)"'); [ "${st%%/*}" != "completed" ]; do sleep 30; done
  [ "${st#*/}" = "success" ] || { echo "erro: $wf em $repo terminou com ${st#*/}: https://github.com/$repo/actions/runs/$id" >&2; exit 1; }
}
# Outputs de um state no S3 (sem terraform init).
tf_out() { # tf_out <state-key> <output>
  aws s3 cp "s3://$BUCKET/$1" - 2>/dev/null | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['outputs']['$2']['value']))"
}
hcl_list() { python3 -c "import sys,json; print(json.dumps(json.loads(sys.argv[1])))" "$1"; } # lista JSON == lista HCL

echo "conta $ACCOUNT | env $ENV ($BRANCH) | state s3://$BUCKET | a partir de: $FROM"

# --- 1. Cluster (VPC + EKS) ----------------------------------------------------
if ! skip cluster; then
  log "1/7 cluster: VPC + EKS (~20 min)"
  # Sem estes dois o stage gateway/ e ignorado (ARNs do ciclo anterior nao valem mais).
  gh variable delete AUTH_LAMBDA_ARN -R "$R_K8S" 2>/dev/null || true
  gh variable delete BACKEND_LISTENER_ARN -R "$R_K8S" 2>/dev/null || true
  run_wf "$R_K8S" cd.yml -f action=apply
fi
K="oficina-infra-k8s/cluster/$ENV.tfstate"
VPC_ID=$(tf_out "$K" vpc_id | tr -d '"'); VPC_CIDR=$(tf_out "$K" vpc_cidr | tr -d '"')
SUBNETS=$(hcl_list "$(tf_out "$K" private_subnet_ids)")
VPC_LINK_SG=$(tf_out "$K" vpc_link_security_group_id | tr -d '"'); LAMBDA_SG=$(tf_out "$K" auth_lambda_security_group_id | tr -d '"')
CLUSTER=$(tf_out "$K" cluster_name | tr -d '"')
log "contratos do cluster"
setvar "$R_DB" VPC_ID "$VPC_ID"; setvar "$R_DB" DB_SUBNET_IDS "$SUBNETS"; setvar "$R_DB" DB_ALLOWED_CIDRS "[\"$VPC_CIDR\"]"
setvar "$R_LAMBDA" SUBNET_IDS "$SUBNETS"; setvar "$R_LAMBDA" SECURITY_GROUP_IDS "[\"$LAMBDA_SG\"]"
setvar "$R_K8S" VPC_LINK_SUBNET_IDS "$SUBNETS"; setvar "$R_K8S" VPC_LINK_SECURITY_GROUP_IDS "[\"$VPC_LINK_SG\"]"
setvar "$R_APP" EKS_CLUSTER_NAME "$CLUSTER"

# --- 2. RDS ----------------------------------------------------------------------
if ! skip db; then
  log "2/7 infra-db: RDS Multi-AZ (~15 min)"
  run_wf "$R_DB" cd.yml -f action=apply
fi
DB_SECRET_ARN=$(tf_out "oficina-infra-db/$ENV.tfstate" secret_arn | tr -d '"'); DB_SECRET_NAME=$(tf_out "oficina-infra-db/$ENV.tfstate" secret_name | tr -d '"')
log "contratos do banco"
setvar "$R_LAMBDA" DB_SECRET_ID "$DB_SECRET_ARN"; setvar "$R_APP" DB_SECRET_ID "$DB_SECRET_NAME"

# --- 3. Lambda: infra + codigo ---------------------------------------------------
if ! skip lambda; then
  log "3/7 auth-lambda: Terraform + deploy de codigo (~8 min)"
  run_wf "$R_LAMBDA" infra.yml -f environment="$ENV" -f action=apply
  run_wf "$R_LAMBDA" cd.yml
fi
FN=$(tf_out "oficina-auth-lambda/$ENV.tfstate" function_name | tr -d '"'); JWT_SECRET_ARN=$(tf_out "oficina-auth-lambda/$ENV.tfstate" jwt_secret_arn | tr -d '"')
ALIAS_ARN=$(aws lambda get-alias --function-name "$FN" --name "$ENV" --query AliasArn --output text)
log "contratos da lambda"
setvar "$R_APP" JWT_SECRET_ID "$JWT_SECRET_ARN"; setvar "$R_K8S" AUTH_LAMBDA_ARN "$ALIAS_ARN"; setvar "$R_LAMBDA" LAMBDA_FUNCTION_NAME "$FN"

# --- 4. App no EKS ---------------------------------------------------------------
if ! skip app; then
  log "4/7 app: build + ECR + EKS + migrations (~10 min)"
  run_wf "$R_APP" cd-aws.yml
fi
aws eks update-kubeconfig --name "$CLUSTER" >/dev/null
NLB=$(kubectl -n oficina get svc oficina-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
LB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='$NLB'].LoadBalancerArn" --output text)
LISTENER=$(aws elbv2 describe-listeners --load-balancer-arn "$LB_ARN" --query 'Listeners[0].ListenerArn' --output text)
log "contrato do backend"; setvar "$R_K8S" BACKEND_LISTENER_ARN "$LISTENER"

# --- 5. Gateway ------------------------------------------------------------------
if ! skip gateway; then
  log "5/7 gateway: API Gateway + VPC Link (~5 min)"
  run_wf "$R_K8S" cd.yml -f action=apply
fi
GW=$(tf_out "oficina-infra-k8s/gateway/$ENV.tfstate" api_base_url | tr -d '"')
log "URL publica: $GW"; setvar "$R_APP" GATEWAY_URL "$GW"

# --- 6. App de novo, com a URL publica (links de aprovacao, CORS) ----------------
if ! skip url; then
  log "6/7 app: redeploy com GATEWAY_URL (~8 min)"
  run_wf "$R_APP" cd-aws.yml
fi

# --- 7. Seeds + smoke ------------------------------------------------------------
if $SEED && ! skip seed; then
  log "7/7 seeds de teste (clientes, catalogo, usuarios staff)"
  kubectl -n oficina exec deploy/oficina-app -c app -- sh -c \
    'for f in prisma/seeds/01_test_data.sql prisma/seeds/03_test_users.sql; do npx prisma db execute --file $f; done' 2>&1 | grep -v Defaulted || true
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
echo "   para derrubar: scripts/aws-destroy-all.sh --yes"
