# Stage messaging — outputs (contratos com os servicos).

output "topic_arns" {
  description = "ARN do topico SNS FIFO de cada produtor (SNS_TOPIC_ARN do servico)."
  value       = { for k, t in aws_sns_topic.this : k => t.arn }
}

output "queue_urls" {
  description = "URL da fila SQS FIFO de cada consumidor (SQS_QUEUE_URL do servico)."
  value       = { for k, q in aws_sqs_queue.this : k => q.url }
}

output "dlq_urls" {
  description = "URL das DLQs (reprocessamento manual)."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.url }
}

output "service_bindings" {
  description = "Topico e fila(s) por servico — o que vai para as vars SNS_TOPIC_ARN / SQS_QUEUE_URL de cada repo."
  value = {
    "os-service" = {
      topic_arn = aws_sns_topic.this["os"].arn
      queue_url = aws_sqs_queue.this["os_eventos"].url
      queues    = { os_eventos = aws_sqs_queue.this["os_eventos"].url, notificacao_eventos = aws_sqs_queue.this["notificacao_eventos"].url }
    }
    "billing-service" = {
      topic_arn = aws_sns_topic.this["billing"].arn
      queue_url = aws_sqs_queue.this["billing_comandos"].url
      queues    = { billing_comandos = aws_sqs_queue.this["billing_comandos"].url }
    }
    "execucao-service" = {
      topic_arn = aws_sns_topic.this["execucao"].arn
      queue_url = aws_sqs_queue.this["execucao_comandos"].url
      queues    = { execucao_comandos = aws_sqs_queue.this["execucao_comandos"].url }
    }
  }
}

output "services_policy_arn" {
  description = "Policy IAM de publicar/consumir (anexar a role dos nodes quando node_role_name nao for informado)."
  value       = aws_iam_policy.services.arn
}

output "ssm_prefix" {
  description = "Prefixo dos parametros SSM com topicos/filas."
  value       = "/${var.name_prefix}/messaging"
}
