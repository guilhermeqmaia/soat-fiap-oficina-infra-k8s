#!/usr/bin/env bash
# Propaga o contrato do stage messaging (SSM) para as vars dos repos dos
# servicos: SNS_TOPIC_ARN (topico que o servico PUBLICA) e SQS_QUEUE_URL
# (fila que o servico CONSOME). O CD de cada servico injeta no ConfigMap.
#
#   scripts/messaging-vars.sh [--profile oficina] [--prefix oficina] [--owner guilhermeqmaia]
set -euo pipefail
PROFILE="oficina"; PREFIX="oficina"; OWNER="${GH_OWNER:-guilhermeqmaia}"
while [ $# -gt 0 ]; do case "$1" in --profile) PROFILE="$2"; shift;; --prefix) PREFIX="$2"; shift;; --owner) OWNER="$2"; shift;; *) echo "flag desconhecida: $1" >&2; exit 1;; esac; shift; done
export AWS_PROFILE="$PROFILE" AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"
ssm() { aws ssm get-parameter --name "/$PREFIX/messaging/$1" --query Parameter.Value --output text; }
setvar() { gh variable set "$2" -R "$OWNER/$1" --body "$3" >/dev/null && echo "   $1 :: $2 = $3"; }
# servico : topico-que-publica : fila-que-consome
for b in "soat-fiap-oficina-mecanica-app:os:os_eventos" \
         "soat-fiap-oficina-billing-service:billing:billing_comandos" \
         "soat-fiap-oficina-execucao-service:execucao:execucao_comandos"; do
  IFS=: read -r repo topic queue <<<"$b"
  setvar "$repo" SNS_TOPIC_ARN "$(ssm "topics/$topic/arn")"
  setvar "$repo" SQS_QUEUE_URL "$(ssm "queues/$queue/url")"
done
# O OS Service tambem consome a fila de notificacao (coreografia, US-F4-12).
setvar soat-fiap-oficina-mecanica-app SQS_NOTIFICACAO_QUEUE_URL "$(ssm queues/notificacao_eventos/url)"
echo "ok — reexecute o CD de cada servico para o ConfigMap receber os valores"
