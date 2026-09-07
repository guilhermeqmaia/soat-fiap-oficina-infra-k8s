# Stage cluster — rede: VPC multi-AZ com subnets publicas (NAT/LBs de borda)
# e privadas (nodes, RDS, Lambda, VPC Link). Nada de workload em subnet
# publica — so o API Gateway e publico (ADR-0005 do repo principal).

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${local.azs[count.index]}"
    # Tag que o EKS/controllers usam para descobrir subnets de LB publico.
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.project_name}-private-${local.azs[count.index]}"
    # Tag para LBs INTERNOS — e onde o NLB interno do app nasce (US-F3-06).
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# NAT unico (na primeira subnet publica): saida de internet para os nodes
# (pull de imagens, Datadog, webhooks). Um por AZ dobraria o custo — para a
# demo do Academy, o trade-off consciente e um unico NAT.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-nat" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-rt-private" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# SG dedicado ao VPC Link do API Gateway (repo: stage gateway/). Egress-only:
# as ENIs do VPC Link so iniciam conexoes em direcao ao NLB interno.
resource "aws_security_group" "vpc_link" {
  name_prefix = "${var.project_name}-vpc-link-"
  description = "ENIs do VPC Link do API Gateway"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Saida para o NLB interno / nodes na VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${var.project_name}-vpc-link" }
}
