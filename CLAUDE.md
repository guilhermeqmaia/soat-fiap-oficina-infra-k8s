# Infra K8s — Oficina Mecânica (Tech Challenge FIAP Fase 3)

## About this repo

Repo **2/4** of the solution: Terraform for the cloud entry point and the
Kubernetes platform of the Oficina Mecânica system.

- `gateway/` — **AWS API Gateway** (HTTP API): public `POST /auth` → CPF
  Lambda (repo 1), Lambda Authorizer (JWT) on the protected catch-all,
  **VPC Link** to the internal ALB, throttling, CORS, JSON access logs.
  Done (US-F3-02).
- `cluster/` — **Amazon EKS**: VPC (public/private subnets, NAT, multi-AZ),
  managed node group, metrics-server, AWS Load Balancer Controller, IRSA.
  To do: `docs/user-stories/f3-05-terraform-cluster-kubernetes.md`
  (use the `/implement-story` skill).

## Architecture rules (non-negotiable)

- **Only the API Gateway is public.** Everything else (EKS, internal ALB, RDS,
  Lambda) lives inside the VPC with no public exposure — no gateway bypass.
- The gateway reaches the app through a **VPC Link → internal ALB listener**
  (produced by the cluster/US-F3-06 work; consumed by `gateway/` variables).
- HTTP API (v2), not REST API: access logs without the account-level
  CloudWatch role (which AWS Academy cannot create), native CORS/throttling,
  VPC Link support, lower cost.
- Single auth Lambda serves both `POST /auth` and the REQUEST authorizer
  (payload 2.0, simple responses).

## AWS Academy constraints (always apply)

- Region **us-east-1**; session credentials expire (~4h) — renew before
  plan/apply.
- **Cannot create IAM roles** — use the existing `LabRole`/`LabInstanceProfile`
  (relevant for EKS node groups and add-ons); prefer designs that need none.
- CI/CD credentials only via **GitHub Actions Secrets**
  (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`).

## Conventions

- Terraform style: Portuguese comments, one file per concern (`versions.tf`,
  `providers.tf`, `variables.tf`, `locals.tf`, resources, `outputs.tf`),
  filled `terraform.tfvars.example`, `default_tags` with
  Project/Fase/Story/ManagedBy. Each directory is an independent stage with
  its own state.
- Validate before pushing: `terraform -chdir=<stage> fmt -check &&
  terraform -chdir=<stage> init -backend=false && terraform -chdir=<stage> validate`.
- Never commit `*.tfvars`, `*.tfstate`, kubeconfigs (see `.gitignore`).
- The gateway's public-route list (`gateway/locals.tf`) must mirror the
  `@Public()` endpoints of the app (repo 4) — when the app adds a public
  endpoint, this repo needs a matching route key.
- Every implemented story gets a QA plan in `docs/qa-plans/` (skill `/qa-plan`).
- `main` is protected: work on branches + PR (solo merges use
  `gh pr merge --admin`). Draft PRs by default; ask before commit/push.
