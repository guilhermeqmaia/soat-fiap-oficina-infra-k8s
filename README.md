# soat-fiap-oficina-infra-k8s

Terraform da infraestrutura de nuvem do **Sistema da Oficina Mecânica**
(Tech Challenge FIAP — Fase 3): API Gateway e, em breve, o cluster **Amazon
EKS**. Repositório **2/4** da solução.

| # | Repositório | Conteúdo |
|---|---|---|
| 1 | [soat-fiap-oficina-auth-lambda](https://github.com/guilhermeqmaia/soat-fiap-oficina-auth-lambda) | Function serverless de autenticação por CPF |
| 2 | **soat-fiap-oficina-infra-k8s** (este) | Terraform do API Gateway + cluster EKS |
| 3 | [soat-fiap-oficina-infra-db](https://github.com/guilhermeqmaia/soat-fiap-oficina-infra-db) | Terraform do banco gerenciado (RDS PostgreSQL) |
| 4 | [soat-fiap-oficina-mecanica-app](https://github.com/guilhermeqmaia/soat-fiap-oficina-mecanica-app) | Aplicação NestJS + manifestos K8s + docs |

## Estrutura

| Diretório | História | Conteúdo |
|---|---|---|
| [`gateway/`](gateway/) | US-F3-02 | AWS API Gateway (HTTP API): rota `/auth` na Lambda, Lambda Authorizer de JWT, VPC Link para o ALB interno do EKS, throttling, CORS e access logs |
| [`observability/`](observability/README.md) | US-F3-10 | Agente Datadog (Helm values), alternativa OSS Prometheus/Grafana e monitores sintéticos de uptime (Terraform) |
| [`cluster/`](cluster/) | US-F3-05 | VPC multi-AZ, cluster EKS + managed node group (LabRole), add-ons (`metrics-server` p/ HPA), SG do VPC Link |

## Credenciais e segredos

Regras deste e dos demais repositórios da solução:

- **Nunca** commitar credenciais: `*.tfvars` reais, `*.tfstate` e kubeconfigs
  estão no `.gitignore` (apenas `*.tfvars.example` é versionado).
- Credenciais de nuvem entram **somente via GitHub Actions Secrets** do
  repositório: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e
  `AWS_SESSION_TOKEN` (AWS Academy Learner Lab — o token de sessão expira a
  cada sessão do lab e precisa ser atualizado: `gh secret set AWS_SESSION_TOKEN`).
- Segredos de runtime (ex.: segredo de assinatura do JWT) vivem no **AWS
  Secrets Manager**, nunca em variável de ambiente commitada.

## Como aplicar

Cada diretório é um stage independente com seu próprio README e state:

```bash
cd gateway
cp terraform.tfvars.example terraform.tfvars   # preencher com outputs reais
terraform init && terraform apply
```

## Qualidade

```bash
for stage in gateway cluster; do
  terraform -chdir=$stage fmt -check && terraform -chdir=$stage init -backend=false && terraform -chdir=$stage validate
done
```

Ordem de apply: **`cluster/` → `gateway/`** (o gateway consome subnets/SG do
cluster e o listener do NLB interno criado pelo deploy do app — US-F3-06).

## CI/CD (US-F3-08)

| Workflow | Quando | O que faz |
|---|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | PR e push | `fmt -check` + `validate` dos stages; **`terraform plan` comentado no PR** (quando há credenciais) |
| [`cd.yml`](.github/workflows/cd.yml) | push em `homolog`/`main` | `apply` automático — `homolog` → homologação, `main` → produção; ordem `cluster` → `gateway` |

Estado remoto: S3 (`TF_STATE_BUCKET`), chave `oficina-infra-k8s/<stage>/<env>.tfstate`
— injetado por *override file* só no CI (local continua com state local).

**Secrets** (por ambiente ou repo): `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN` (Academy — renovar por sessão do lab), `TF_STATE_BUCKET`
(ou `AWS_ROLE_ARN` para OIDC em conta própria).
**Vars**: `LAB_ROLE_ARN` (cluster); `AUTH_LAMBDA_ARN`, `BACKEND_LISTENER_ARN`,
`VPC_LINK_SUBNET_IDS`, `VPC_LINK_SECURITY_GROUP_IDS` (gateway — outputs das
US-F3-01/05/06). Sem eles o apply do stage é **ignorado com aviso** (não falha).

**Deploy ativo:** URL pública do gateway = output `api_base_url` do stage
`gateway/` (aparece no summary do run de CD). <!-- atualizar com a URL após o primeiro apply -->

## Documentação

- [docs/user-stories/](docs/user-stories/) — US-F3-02 (gateway), US-F3-05
  (cluster EKS) e US-F3-10 (observabilidade de infra)
- [docs/tech-challenges/fase-3-tech-challenge.pdf](docs/tech-challenges/fase-3-tech-challenge.pdf) — enunciado
- [docs/qa-plans/](docs/qa-plans/) — planos de QA (gerados com a skill `/qa-plan`)
