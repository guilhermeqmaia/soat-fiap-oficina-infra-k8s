# Stage cluster — EKS gerenciado com managed node group e add-ons.
#
# IAM em iam.tf: LabRole (AWS Academy) ou roles criadas aqui (conta propria).
# Consequencias assumidas para funcionar nos dois modos:
#   - sem IRSA -> sem AWS Load Balancer Controller (precisaria de role);
#   - o app e exposto por NLB INTERNO via provider in-tree do Kubernetes
#     (annotations no Service — US-F3-06), que nao exige IAM extra;
#   - metrics-server (pre-requisito do HPA) entra como ADD-ON gerenciado.

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = local.cluster_role_arn
  version  = var.kubernetes_version

  vpc_config {
    # Nodes/pods em subnets privadas; as publicas ficam registradas para o
    # control plane poder criar LBs publicos se um dia for preciso.
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_public_access  = true # kubectl do time/CI vem da internet (Academy)
    endpoint_private_access = true
  }

  enabled_cluster_log_types = ["api", "audit"]

  # Quem roda o apply (CI via OIDC ou credencial do lab) vira admin do cluster.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_cloudwatch_log_group.cluster, aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = local.node_role_arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # O desired_size passa a ser gerenciado pelo autoscaling apos o bootstrap.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.nodes]
}

# Add-ons gerenciados. metrics-server e o pre-requisito do HPA (US-F3-06);
# como add-on, dispensa helm/kubectl neste stage.
resource "aws_eks_addon" "this" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy", "metrics-server"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}

# O trafego do VPC Link (gateway) chega ao NLB interno, que encaminha para os
# NodePorts. Libera a VPC inteira no SG do cluster: tudo aqui dentro e privado
# e a autorizacao de verdade acontece no gateway + app (defesa em profundidade).
resource "aws_vpc_security_group_ingress_rule" "nodes_from_vpc" {
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = "Trafego interno da VPC (VPC Link, NLB, NodePort)"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 0
  to_port           = 65535
}
