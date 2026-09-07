# Stage cluster — EKS: locals derivados.
locals {
  cluster_name = "${var.project_name}-eks"

  # 2 AZs bastam para o requisito de HA multi-AZ sem triplicar custo de NAT.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # /20 dentro do /16: 4094 IPs por subnet (o CNI do EKS consome um IP por pod).
  public_subnet_cidrs  = [for i in range(2) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i in range(2) : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

data "aws_availability_zones" "available" {
  state = "available"
}
