# Stage cluster — VPC + Amazon EKS (US-F3-05)

Provisiona a **rede da solução inteira** e o **cluster Kubernetes gerenciado**:

- **VPC multi-AZ** (2 AZs): 2 subnets públicas (NAT/IGW) + 2 privadas (nodes,
  RDS, Lambda, VPC Link) — nenhum workload público, só o API Gateway
  ([ADR-0005](https://github.com/guilhermeqmaia/soat-fiap-oficina-mecanica-app/blob/main/docs/arquitetura/adr/ADR-0005-api-gateway.md));
- **EKS** com managed node group (2–4 nodes, multi-AZ) e add-ons gerenciados:
  `vpc-cni`, `coredns`, `kube-proxy` e **`metrics-server`** (pré-requisito do
  HPA — [ADR-0002](https://github.com/guilhermeqmaia/soat-fiap-oficina-mecanica-app/blob/main/docs/arquitetura/adr/ADR-0002-hpa-autoescalonamento.md));
- **SG do VPC Link** e liberação de tráfego interno da VPC até os nodes.

## Topologia

```
                    Internet
                       │
              ┌────────▼────────┐
              │   API Gateway   │  (stage gateway/ — única entrada pública)
              └────────┬────────┘
                VPC Link (ENIs nas subnets privadas)
┌──────────────────────┼──────────────── VPC 10.0.0.0/16 ─────────┐
│  públicas: [NAT, IGW]│                                          │
│  privadas: ┌─────────▼──────────┐   ┌──────────┐  ┌──────────┐  │
│            │ NLB interno        │   │ RDS      │  │ Lambda   │  │
│            │  └► EKS nodes 2-4  │   │ (repo 3) │  │ (repo 1) │  │
│            │     app + HPA      │   └──────────┘  └──────────┘  │
│            └────────────────────┘                               │
└─────────────────────────────────────────────────────────────────┘
```

## Decisões do AWS Academy (importantes)

| Restrição do lab | Consequência |
|---|---|
| Não cria IAM roles | **LabRole** é a role do cluster **e** do node group (`lab_role_arn`) |
| Não cria OIDC provider | **Sem IRSA** → sem AWS Load Balancer Controller |
| Sem LB Controller | O app é exposto por **NLB interno via provider in-tree** do Kubernetes — basta anotar o Service (US-F3-06), sem IAM extra |
| Sessão expira (~4h) | Renove as credenciais antes de `plan`/`apply`; o state local segue válido |

Anotações do Service da aplicação (US-F3-06) que criam o NLB interno:

```yaml
service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
service.beta.kubernetes.io/aws-load-balancer-internal: "true"
```

## Como aplicar

```bash
cd cluster
cp terraform.tfvars.example terraform.tfvars   # ARN da LabRole
terraform init && terraform apply              # ~15 min (EKS)

# Conectar o kubectl:
eval "$(terraform output -raw kubeconfig_command)"
kubectl get nodes          # 2 nodes Ready
kubectl top nodes          # metrics-server respondendo (HPA ok)
```

## Contratos (quem consome cada output)

| Output | Consumidor |
|---|---|
| `private_subnet_ids` | `gateway/` (`vpc_link_subnet_ids`) · repo **infra-db** (subnet group do RDS) · repo **auth-lambda** (`vpc_subnet_ids`) |
| `vpc_link_security_group_id` | `gateway/` (`vpc_link_security_group_ids`) |
| `vpc_id` / `vpc_cidr` | repo **infra-db** (SG do RDS: ingress só da VPC) |
| `cluster_name` / `kubeconfig_command` | repo **app** (deploy US-F3-06, CI/CD US-F3-08) |
| listener ARN do NLB interno | criado pelo Service do app (US-F3-06); obtido via `aws elbv2 describe-listeners` e passado ao `gateway/` (`backend_listener_arn`) |

## Escalabilidade

- **Pods**: HPA (CPU/mem 70%, 2–10 réplicas — manifesto no repo do app) usando
  o `metrics-server` deste stage.
- **Nodes**: `scaling_config` 2–4 (o `desired_size` fica por conta do
  autoscaling após o bootstrap — `ignore_changes`).

## Qualidade

```bash
terraform fmt -check && terraform init -backend=false && terraform validate
```

## ⚠️ Custos (fora do free tier)

EKS (~US$ 0,10/h) + 2× t3.medium + NAT Gateway (~US$ 0,045/h + tráfego).
**Destrua quando não estiver demonstrando**: `terraform destroy` (antes,
remova o Service do app para o NLB in-tree não ficar órfão).
