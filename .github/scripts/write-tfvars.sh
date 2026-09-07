#!/usr/bin/env bash
# Gera o tfvars do CI emitindo APENAS variaveis realmente definidas nas
# GitHub vars — os defaults continuam sendo os do variables.tf de cada stage
# (fonte unica; evita o drift apontado no code review da Lambda).
set -euo pipefail

stage="$1"
out="$2"
: > "$out"

emit() { # emit <nome-tf> <valor>
  local name="$1" value="$2"
  [ -n "$value" ] && echo "$name = \"$value\"" >> "$out"
}
emit_raw() { # listas/objetos ja em sintaxe HCL, ex.: ["subnet-a","subnet-b"]
  local name="$1" value="$2"
  [ -n "$value" ] && echo "$name = $value" >> "$out"
}

case "$stage" in
  cluster)
    emit lab_role_arn "${LAB_ROLE_ARN:-}"
    ;;
  gateway)
    emit auth_lambda_arn "${AUTH_LAMBDA_ARN:-}"
    emit backend_listener_arn "${BACKEND_LISTENER_ARN:-}"
    emit_raw vpc_link_subnet_ids "${VPC_LINK_SUBNET_IDS:-}"
    emit_raw vpc_link_security_group_ids "${VPC_LINK_SECURITY_GROUP_IDS:-}"
    ;;
esac

echo "tfvars gerado para $stage:" && cat "$out"
