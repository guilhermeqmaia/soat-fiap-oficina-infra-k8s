#!/usr/bin/env bash
# Rotaciona as credenciais temporarias do AWS Academy Learner Lab nos 4 repos
# do projeto (GitHub Actions Secrets). O lab entrega chaves novas a cada
# sessao (~4h), entao este script precisa rodar toda vez que o lab e iniciado.
#
# Fonte das credenciais (bloco "AWS CLI: Show" do painel AWS Details):
#   scripts/aws-academy-rotate.sh                 # le ~/.aws/credentials [default]
#   scripts/aws-academy-rotate.sh --paste         # le da area de transferencia (pbpaste)
#   scripts/aws-academy-rotate.sh --stdin < bloco # le de stdin
#   scripts/aws-academy-rotate.sh --profile lab   # outro profile do ~/.aws/credentials
#
# Flags:
#   --save      grava o bloco lido em ~/.aws/credentials (profile escolhido)
#   --dispatch  dispara o workflow de CD (main) em cada repo apos rotacionar
#   --dry-run   mostra o que faria sem gravar nada
set -euo pipefail

OWNER="${GH_OWNER:-guilhermeqmaia}"
REPOS="${GH_REPOS:-soat-fiap-oficina-mecanica-app soat-fiap-oficina-infra-k8s soat-fiap-oficina-infra-db soat-fiap-oficina-auth-lambda}"
PROFILE="default"
SOURCE="file"
SAVE=false
DISPATCH=false
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --paste) SOURCE="paste" ;;
    --stdin) SOURCE="stdin" ;;
    --profile) PROFILE="$2"; shift ;;
    --save) SAVE=true ;;
    --dispatch) DISPATCH=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 1 ;;
  esac
  shift
done

# --- 1. Obter o bloco INI -------------------------------------------------
case "$SOURCE" in
  paste) block="$(pbpaste)" ;;
  stdin) block="$(cat)" ;;
  file)
    creds="${HOME}/.aws/credentials"
    [ -f "$creds" ] || { echo "erro: $creds nao existe (use --paste ou --stdin)" >&2; exit 1; }
    # extrai apenas a secao [PROFILE]
    block="$(awk -v p="[$PROFILE]" '$0==p{f=1;next} /^\[/{f=0} f' "$creds")"
    ;;
esac

ini_value() { echo "$block" | sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" | head -1 | tr -d '\r'; }
AWS_ACCESS_KEY_ID="$(ini_value aws_access_key_id)"
AWS_SECRET_ACCESS_KEY="$(ini_value aws_secret_access_key)"
AWS_SESSION_TOKEN="$(ini_value aws_session_token)"

for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [ -n "${!v}" ] || { echo "erro: $v nao encontrado no bloco de credenciais" >&2; exit 1; }
done
echo "credenciais lidas: ${AWS_ACCESS_KEY_ID:0:4}**** (token ${#AWS_SESSION_TOKEN} chars)"

# --- 2. Validar na AWS (se o CLI existir) ---------------------------------
if command -v aws >/dev/null; then
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION=us-east-1
  aws sts get-caller-identity --output text --query 'Arn' \
    || { echo "erro: credenciais invalidas/expiradas — inicie o lab de novo" >&2; exit 1; }
fi

# --- 3. Salvar localmente (opcional) --------------------------------------
if $SAVE && ! $DRY_RUN; then
  mkdir -p "$HOME/.aws"; touch "$HOME/.aws/credentials"; chmod 600 "$HOME/.aws/credentials"
  tmp="$(mktemp)"
  awk -v p="[$PROFILE]" '$0==p{skip=1;next} /^\[/{skip=0} !skip' "$HOME/.aws/credentials" > "$tmp"
  {
    cat "$tmp"; echo "[$PROFILE]"
    echo "aws_access_key_id = $AWS_ACCESS_KEY_ID"
    echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY"
    echo "aws_session_token = $AWS_SESSION_TOKEN"
  } > "$HOME/.aws/credentials"
  rm -f "$tmp"
  echo "~/.aws/credentials [$PROFILE] atualizado"
fi

# --- 4. Rotacionar os secrets nos repos -----------------------------------
for repo in $REPOS; do
  echo "== $OWNER/$repo"
  for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
    if $DRY_RUN; then echo "   (dry-run) gh secret set $name"; continue; fi
    gh secret set "$name" -R "$OWNER/$repo" --body "${!name}" >/dev/null && echo "   $name ok"
  done
done

# --- 5. Disparar CD (opcional) --------------------------------------------
if $DISPATCH && ! $DRY_RUN; then
  for repo in $REPOS; do
    wf="cd.yml"; [ "$repo" = "soat-fiap-oficina-mecanica-app" ] && wf="cd-aws.yml"
    gh workflow run "$wf" -R "$OWNER/$repo" --ref main && echo "   $repo: $wf disparado (main)"
  done
fi

echo "pronto — credenciais valem ate o fim da sessao do lab (~4h)."
