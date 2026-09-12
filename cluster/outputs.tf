# Stage cluster — outputs (contratos com os outros repos/stages).

output "vpc_id" {
  description = "VPC de toda a solucao (consumida pelo repo infra-db para o RDS)."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR da VPC (regras de SG em outros stages)."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Subnets privadas: nodes do EKS, RDS (repo infra-db), Lambda (repo auth-lambda) e vpc_link_subnet_ids do stage gateway/."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Subnets publicas (NAT; LBs publicos se necessario)."
  value       = aws_subnet.public[*].id
}

output "vpc_link_security_group_id" {
  description = "SG das ENIs do VPC Link — entrada vpc_link_security_group_ids do stage gateway/."
  value       = aws_security_group.vpc_link.id
}

output "cluster_name" {
  description = "Nome do cluster (aws eks update-kubeconfig --name <este valor>)."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint do control plane."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "SG gerenciado do cluster (ingress de VPC ja liberado para o VPC Link/NLB)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "kubeconfig_command" {
  description = "Comando pronto para conectar o kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "cluster_role_arn" {
  description = "Role do control plane (LabRole no Academy ou criada em iam.tf)."
  value       = local.cluster_role_arn
}

output "node_role_arn" {
  description = "Role dos nodes (LabRole no Academy ou criada em iam.tf)."
  value       = local.node_role_arn
}

output "auth_lambda_security_group_id" {
  description = "SG da Lambda de auth por CPF — entrada security_group_ids do repo auth-lambda (var SECURITY_GROUP_IDS no CI)."
  value       = aws_security_group.auth_lambda.id
}
