# Stage messaging — contrato de saida em SSM Parameter Store.
#
# O CD de cada servico (e o scripts/messaging-vars.sh) le daqui o topico e a
# fila que lhe pertencem, sem depender do tfstate deste stage.
resource "aws_ssm_parameter" "topic_arn" {
  for_each = local.topics

  name  = "/${var.name_prefix}/messaging/topics/${each.key}/arn"
  type  = "String"
  value = aws_sns_topic.this[each.key].arn
}

resource "aws_ssm_parameter" "queue_url" {
  for_each = local.queues

  name  = "/${var.name_prefix}/messaging/queues/${each.key}/url"
  type  = "String"
  value = aws_sqs_queue.this[each.key].url
}

resource "aws_ssm_parameter" "dlq_url" {
  for_each = local.queues

  name  = "/${var.name_prefix}/messaging/queues/${each.key}/dlq_url"
  type  = "String"
  value = aws_sqs_queue.dlq[each.key].url
}
