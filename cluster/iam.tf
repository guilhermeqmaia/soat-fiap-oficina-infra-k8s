# Stage cluster — IAM do EKS.
#
# Dois modos, escolhidos por `lab_role_arn`:
#   - AWS Academy: `lab_role_arn` preenchido -> a LabRole e usada como role do
#     cluster E do node group e NADA e criado aqui (o lab nao permite IAM roles).
#   - Conta propria: `lab_role_arn` vazio -> este arquivo cria as duas roles com
#     as policies gerenciadas da AWS (menor privilegio que a LabRole).
locals {
  create_roles     = var.lab_role_arn == ""
  cluster_role_arn = local.create_roles ? aws_iam_role.cluster[0].arn : var.lab_role_arn
  node_role_arn    = local.create_roles ? aws_iam_role.nodes[0].arn : var.lab_role_arn
}

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  count              = local.create_roles ? 1 : 0
  name               = "${local.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count      = local.create_roles ? 1 : 0
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "nodes_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  count              = local.create_roles ? 1 : 0
  name               = "${local.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume.json
}

# Worker + CNI + pull do ECR (imagens do app) + SSM (acesso ao node sem SSH).
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = local.create_roles ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]) : toset([])

  role       = aws_iam_role.nodes[0].name
  policy_arn = each.value
}

# Quem roda o apply ja vira admin (bootstrap_cluster_creator_admin_permissions).
# Outros principals (ex.: usuario IAM do time no laptop) entram por access entry.
resource "aws_eks_access_entry" "admins" {
  for_each      = toset(var.cluster_admin_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admins" {
  for_each      = toset(var.cluster_admin_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}
