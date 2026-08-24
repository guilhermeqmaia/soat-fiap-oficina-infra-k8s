# US-F3-05: Terraform — Cluster Kubernetes Gerenciado (EKS)

**User Story:** Como time de plataforma, quero provisionar um cluster Kubernetes gerenciado e escalavel (EKS) via Terraform, para rodar a aplicacao com alta disponibilidade e autoescalonamento.

**Prioridade:** Alta
**Story Points:** 8
**Status:** To Do
**DDD Domain:** Infraestrutura
**DDD Layer:** —
**Repositorio:** 2 — `soat-fiap-oficina-infra-k8s`

## Contexto

Migra do cluster kind (Fase 2) para **Amazon EKS**. Repositorio dedicado com
CI/CD e deploy automatico ([f3-08](f3-08-cicd-multi-repo.md)). O cluster hospeda
a aplicacao ([f3-06](f3-06-deploy-aplicacao-eks.md)) e a stack de observabilidade
([f3-10](f3-10-observabilidade-apm.md)).

## Criterios de Aceite

- [ ] Terraform provisiona **VPC** (subnets publicas/privadas, NAT, multi-AZ) e **cluster EKS**
- [ ] **Managed node group** com escalabilidade (cluster autoscaler ou Karpenter)
- [ ] **metrics-server** instalado (pre-requisito do HPA)
- [ ] Add-ons: **AWS Load Balancer Controller** (ingress/ALB), CNI, CoreDNS
- [ ] **IRSA** (IAM Roles for Service Accounts) para pods que acessam AWS (Secrets Manager, ECR, observabilidade)
- [ ] Escalabilidade comprovada: HPA por CPU/memoria (min/max) funcionando no cluster gerenciado
- [ ] Integracao com o **API Gateway** ([f3-02](f3-02-api-gateway.md)) — ingress/ALB alcancavel pelo gateway
- [ ] **Remote state** (S3 + DynamoDB lock)
- [ ] Parametrizacao por ambiente (homolog/prod)
- [ ] `terraform fmt`/`validate`/`plan` no CI; `apply` no deploy automatico
- [ ] Outputs: nome do cluster, endpoint, kubeconfig/OIDC — consumidos pelo repo da aplicacao
- [ ] README do repo: recursos, como aplicar, diagrama de rede, variaveis, custo estimado

## Notas

- Reaproveitar o modo "cloud" (EKS) ja esbocado no Terraform da Fase 2 como ponto de partida.
