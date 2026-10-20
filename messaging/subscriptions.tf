# Stage messaging — assinaturas SNS -> SQS com filtro por `type`.
#
# `filter_policy_scope = MessageAttributes`: o SnsPublisher do kit envia `type`
# como message attribute. Entrega crua (raw) para o consumidor receber o
# envelope JSON direto no body.
resource "aws_sns_topic_subscription" "this" {
  for_each = local.subscriptions

  topic_arn            = aws_sns_topic.this[each.value.topic].arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this[each.value.queue].arn
  raw_message_delivery = true
  filter_policy_scope  = "MessageAttributes"
  filter_policy        = jsonencode({ type = each.value.types })

  depends_on = [aws_sqs_queue_policy.this]
}
