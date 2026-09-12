#!/usr/bin/env bash
# Prepara UMA VEZ a conta do AWS Academy Learner Lab e os secrets/vars estaveis
# dos 4 repos (os que nao rotacionam por sessao). Idempotente: pode rodar de
# novo sem efeito colateral. Requer credenciais validas (rode antes
# scripts/aws-academy-rotate.sh --paste --save).
#
#   scripts/aws-academy-bootstrap.sh [--profile default] [--dry-run]
#
# Cria: bucket S3 do state do Terraform (versionado, criptografado, privado)
#       e tabela DynamoDB de lock; grava TF_STATE_BUCKET / TF_STATE_LOCK_TABLE
#       (secrets) e LAB_ROLE_ARN / LAMBDA_ROLE_ARN (vars) nos repos.
set -euo pipefail

OWNER="${GH_OWNER:-guilhermeqmaia}"
REGION="${AWS_REGION:-us-east-1}"
PROFILE="default"
DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 1 ;;
  esac
  shift
done

export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="$REGION"
command -v aws >/dev/null || { echo "erro: aws CLI nao instalado (brew install awscli)" >&2; exit 1; }
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)" \
  || { echo "erro: credenciais invalidas/expiradas — rode aws-academy-rotate.sh" >&2; exit 1; }

BUCKET="${TF_STATE_BUCKET:-soat-oficina-tfstate-$ACCOUNT}"
LOCK_TABLE="${TF_STATE_LOCK_TABLE:-soat-oficina-tflock}"
LAB_ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/LabRole"
echo "conta $ACCOUNT | bucket $BUCKET | lock $LOCK_TABLE | $LAB_ROLE_ARN"
$DRY_RUN && { echo "(dry-run) nada gravado"; exit 0; }

# --- 1. Bucket do state ---------------------------------------------------
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "bucket ja existe"
else
  # us-east-1 nao aceita LocationConstraint
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  echo "bucket criado"
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# --- 2. Tabela de lock ----------------------------------------------------
if aws dynamodb describe-table --table-name "$LOCK_TABLE" >/dev/null 2>&1; then
  echo "tabela de lock ja existe"
else
  aws dynamodb create-table --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  echo "tabela de lock criada"
fi

# --- 3. Secrets/vars estaveis nos repos -----------------------------------
set_secret() { gh secret set "$2" -R "$OWNER/$1" --body "$3" >/dev/null && echo "   $1: secret $2"; }
set_var()    { gh variable set "$2" -R "$OWNER/$1" --body "$3" >/dev/null && echo "   $1: var $2"; }

for repo in soat-fiap-oficina-infra-db soat-fiap-oficina-infra-k8s soat-fiap-oficina-auth-lambda; do
  set_secret "$repo" TF_STATE_BUCKET "$BUCKET"
done
set_secret soat-fiap-oficina-infra-db TF_STATE_LOCK_TABLE "$LOCK_TABLE"
set_var soat-fiap-oficina-infra-db  LAB_ROLE_ARN "$LAB_ROLE_ARN"
set_var soat-fiap-oficina-infra-k8s LAB_ROLE_ARN "$LAB_ROLE_ARN"
set_var soat-fiap-oficina-auth-lambda LAMBDA_ROLE_ARN "$LAB_ROLE_ARN"
for repo in soat-fiap-oficina-infra-db soat-fiap-oficina-infra-k8s soat-fiap-oficina-auth-lambda soat-fiap-oficina-mecanica-app; do
  set_var "$repo" AWS_REGION "$REGION"
done

echo "pronto — as vars que dependem de outputs (VPC_ID, EKS_CLUSTER_NAME, *_ARN...) entram apos cada apply."
