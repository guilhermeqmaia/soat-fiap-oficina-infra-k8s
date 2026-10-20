# Stage messaging — topologia da RFC-0006 (mesma do scripts/messaging-local.sh do kit).
#
# Topicos SNS FIFO por PRODUTOR; filas SQS FIFO por CONSUMIDOR; assinaturas
# com filtro por `type` (message attribute do envelope — ADR-0009) e entrega
# crua (o consumidor do kit aceita os dois formatos).
locals {
  topics = {
    os       = "${var.name_prefix}-os"
    execucao = "${var.name_prefix}-execucao"
    billing  = "${var.name_prefix}-billing"
  }

  queues = {
    execucao_comandos   = "${var.name_prefix}-execucao-comandos"
    billing_comandos    = "${var.name_prefix}-billing-comandos"
    os_eventos          = "${var.name_prefix}-os-eventos"
    notificacao_eventos = "${var.name_prefix}-notificacao-eventos"
  }

  # Assinaturas: fila <- topico, com os `type`s aceitos (docs/contratos/asyncapi.yaml do hub).
  subscriptions = {
    execucao_comandos_de_os = {
      queue = "execucao_comandos"
      topic = "os"
      types = ["execucao.enfileirar", "execucao.iniciar", "execucao.liberar-reservas"]
    }
    billing_comandos_de_os = {
      queue = "billing_comandos"
      topic = "os"
      types = ["billing.gerar-orcamento", "billing.cancelar-orcamento"]
    }
    os_eventos_de_execucao = {
      queue = "os_eventos"
      topic = "execucao"
      types = ["execucao.enfileirada", "execucao.recusada", "execucao.diagnostico-concluido", "execucao.iniciada", "execucao.finalizada", "execucao.reservas-liberadas"]
    }
    os_eventos_de_billing = {
      queue = "os_eventos"
      topic = "billing"
      types = ["billing.orcamento-gerado", "billing.orcamento-aprovado", "billing.orcamento-rejeitado", "billing.pagamento-aprovado", "billing.pagamento-recusado", "billing.orcamento-cancelado"]
    }
    notificacao_de_billing = {
      queue = "notificacao_eventos"
      topic = "billing"
      types = ["billing.orcamento-gerado", "billing.orcamento-aprovado", "billing.pagamento-aprovado", "billing.pagamento-recusado"]
    }
    notificacao_de_os = {
      queue = "notificacao_eventos"
      topic = "os"
      types = ["os.aberta", "os.finalizada", "os.cancelada", "os.entregue"]
    }
  }

  # Quem consome cada fila — vira parametro SSM para o CD dos servicos.
  queue_owner = {
    execucao_comandos   = "execucao-service"
    billing_comandos    = "billing-service"
    os_eventos          = "os-service"
    notificacao_eventos = "os-service"
  }
  topic_owner = {
    os       = "os-service"
    execucao = "execucao-service"
    billing  = "billing-service"
  }
}
