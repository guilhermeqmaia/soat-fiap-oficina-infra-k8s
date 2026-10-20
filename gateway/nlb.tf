# Stage gateway — NLB interno UNICO com um target group/listener por servico (ADR-0013).
#
# Por que aqui e nao via Service LoadBalancer do Kubernetes (Fase 3): tres
# Services LoadBalancer = tres NLBs (custo x3) e tres ARNs para o gateway
# descobrir. Um NLB gerenciado pelo Terraform, com target groups nos NodePorts
# fixos de cada servico, da ao gateway um contrato estavel e barato. Sem AWS
# Load Balancer Controller (exigiria IRSA — nao disponivel no Academy).

data "aws_eks_node_group" "default" {
  cluster_name    = var.cluster_name
  node_group_name = var.node_group_name
}

resource "aws_lb" "internal" {
  name               = "${var.project_name}-svcs"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.vpc_link_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-svcs"
  }
}

resource "aws_lb_target_group" "service" {
  for_each = var.services

  name        = "${var.project_name}-${each.key}"
  port        = each.value.node_port
  protocol    = "TCP"
  target_type = "instance" # nodes do managed node group (NodePort)
  vpc_id      = var.vpc_id

  # Health check HTTP no /health do servico (liveness do kit): um node so
  # recebe trafego do servico X se o kube-proxy entrega ao pod de X nele.
  health_check {
    protocol            = "HTTP"
    path                = "/health"
    port                = "traffic-port"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  deregistration_delay = 30

  tags = {
    Name    = "${var.project_name}-${each.key}"
    Servico = each.key
  }
}

resource "aws_lb_listener" "service" {
  for_each = var.services

  load_balancer_arn = aws_lb.internal.arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }
}

# Registra o ASG do node group em cada target group (novos nodes entram sozinhos).
resource "aws_autoscaling_attachment" "service" {
  for_each = var.services

  autoscaling_group_name = data.aws_eks_node_group.default.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.service[each.key].arn
}
