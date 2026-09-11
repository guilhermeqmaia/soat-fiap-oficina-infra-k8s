#!/usr/bin/env bash
# Prepara UMA VEZ uma conta AWS propria (nao-Academy) para o CI/CD dos 4 repos:
#   1. bucket S3 do state do Terraform + tabela DynamoDB de lock
#   2. provider OIDC do GitHub + role `github-actions-oficina` (assumida pelos
#      workflows via `AWS_ROLE_ARN` — sem chave estatica, sem rotacao)
#   3. AWS Budget com alerta por e-mail
#   4. secrets/vars estaveis nos 4 repos (gh CLI)
# Idempotente. Requer um profile local com AdministratorAccess.
#
#   scripts/aws-account-bootstrap.sh --email voce@exemplo.com [--profile oficina] [--budget 20] [--dry-run]
set -euo pipefail

OWNER="${GH_OWNER:-guilhermeqmaia}"
REPOS="soat-fiap-oficina-mecanica-app soat-fiap-oficina-infra-k8s soat-fiap-oficina-infra-db soat-fiap-oficina-auth-lambda"
REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="github-actions-oficina"
PROFILE="oficina"
BUDGET=20
EMAIL=""
DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift ;;
    --email) EMAIL="$2"; shift ;;
    --budget) BUDGET="$2"; shift ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 1 ;;
  esac
  shift
done
[ -n "$EMAIL" ] || { echo "erro: --email obrigatorio (destino do alerta de budget)" >&2; exit 1; }

export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="$REGION"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${TF_STATE_BUCKET:-soat-oficina-tfstate-$ACCOUNT}"
LOCK_TABLE="${TF_STATE_LOCK_TABLE:-soat-oficina-tflock}"
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE_NAME}"
echo "conta $ACCOUNT | bucket $BUCKET | lock $LOCK_TABLE | role $ROLE_ARN | budget USD $BUDGET -> $EMAIL"
$DRY_RUN && { echo "(dry-run) nada gravado"; exit 0; }

# --- 1. Backend do Terraform ---------------------------------------------
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then echo "bucket ja existe"; else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null; echo "bucket criado"; fi
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
if aws dynamodb describe-table --table-name "$LOCK_TABLE" >/dev/null 2>&1; then echo "tabela de lock ja existe"; else
  aws dynamodb create-table --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST >/dev/null
  echo "tabela de lock criada"; fi

# --- 2. OIDC do GitHub + role ---------------------------------------------
OIDC_ARN="arn:aws:iam::${ACCOUNT}:oidc-provider/token.actions.githubusercontent.com"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "provider OIDC ja existe"
else
  aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd >/dev/null
  echo "provider OIDC criado"
fi
subs=""; for r in $REPOS; do subs="$subs\"repo:${OWNER}/${r}:*\","; done
trust=$(cat <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"$OIDC_ARN"},
 "Action":"sts:AssumeRoleWithWebIdentity","Condition":{
   "StringEquals":{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},
   "StringLike":{"token.actions.githubusercontent.com:sub":[${subs%,}]}}}]}
JSON
)
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$trust"; echo "role ja existe (trust atualizado)"
else
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$trust" \
    --description "GitHub Actions dos repos soat-fiap-oficina-* (Terraform + deploy)" --max-session-duration 7200 >/dev/null
  echo "role criada"
fi
# Projeto academico: a role provisiona VPC/EKS/RDS/Lambda/IAM — AdministratorAccess.
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# --- 3. Budget ------------------------------------------------------------
if aws budgets describe-budget --account-id "$ACCOUNT" --budget-name oficina-mensal >/dev/null 2>&1; then
  echo "budget ja existe"
else
  aws budgets create-budget --account-id "$ACCOUNT" \
    --budget "{\"BudgetName\":\"oficina-mensal\",\"BudgetLimit\":{\"Amount\":\"$BUDGET\",\"Unit\":\"USD\"},\"TimeUnit\":\"MONTHLY\",\"BudgetType\":\"COST\"}" \
    --notifications-with-subscribers "[
      {\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":50,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"$EMAIL\"}]},
      {\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":100,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"$EMAIL\"}]}]"
  echo "budget criado (alertas em 50% e 100% de USD $BUDGET/mes)"
fi

# --- 4. Secrets/vars nos repos --------------------------------------------
set_secret() { gh secret set "$2" -R "$OWNER/$1" --body "$3" >/dev/null && echo "   $1: secret $2"; }
set_var()    { gh variable set "$2" -R "$OWNER/$1" --body "$3" >/dev/null && echo "   $1: var $2"; }
for repo in $REPOS; do
  set_secret "$repo" AWS_ROLE_ARN "$ROLE_ARN"
  set_var "$repo" AWS_REGION "$REGION"
done
for repo in soat-fiap-oficina-infra-db soat-fiap-oficina-infra-k8s soat-fiap-oficina-auth-lambda; do
  set_secret "$repo" TF_STATE_BUCKET "$BUCKET"
done
set_secret soat-fiap-oficina-infra-db TF_STATE_LOCK_TABLE "$LOCK_TABLE"

echo "pronto — AWS_ROLE_ARN=$ROLE_ARN (nao expira)."
