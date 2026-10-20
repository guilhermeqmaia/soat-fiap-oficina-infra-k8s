# Stage messaging — topicos SNS FIFO (um por servico produtor).
#
# FIFO: a ordem por OS e garantida pelo MessageGroupId (= correlationId do
# envelope); ContentBasedDeduplication desligado porque o produtor envia o
# MessageDeduplicationId (= id do envelope / outbox).
resource "aws_sns_topic" "this" {
  for_each = local.topics

  name                        = "${each.value}.fifo"
  fifo_topic                  = true
  content_based_deduplication = false

  tags = {
    Name     = each.value
    Produtor = local.topic_owner[each.key]
  }
}
