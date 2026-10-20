# Stage messaging — filas SQS FIFO (uma por consumidor) com DLQ.

resource "aws_sqs_queue" "dlq" {
  for_each = local.queues

  name                      = "${each.value}-dlq.fifo"
  fifo_queue                = true
  message_retention_seconds = var.dlq_retention_seconds

  tags = {
    Name       = "${each.value}-dlq"
    Consumidor = local.queue_owner[each.key]
  }
}

resource "aws_sqs_queue" "this" {
  for_each = local.queues

  name                       = "${each.value}.fifo"
  fifo_queue                 = true
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = 20 # long polling (o SqsConsumer do kit usa WaitTimeSeconds=20)

  # Deduplicacao de 5 min do proprio SQS FIFO e a 1a barreira; a 2a e a tabela
  # processed_messages do consumidor (ADR-0009) — cobre reentregas apos 5 min.
  content_based_deduplication = false
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name       = each.value
    Consumidor = local.queue_owner[each.key]
  }
}

# Permite que o SQS mova mensagens da fila principal para a DLQ.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = local.queues

  queue_url = aws_sqs_queue.dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this[each.key].arn]
  })
}

# Cada fila aceita SendMessage apenas dos topicos que a alimentam.
data "aws_iam_policy_document" "queue" {
  for_each = local.queues

  statement {
    sid     = "AllowSnsFanout"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    resources = [aws_sqs_queue.this[each.key].arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [for s in local.subscriptions : aws_sns_topic.this[s.topic].arn if s.queue == each.key]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  for_each = local.queues

  queue_url = aws_sqs_queue.this[each.key].id
  policy    = data.aws_iam_policy_document.queue[each.key].json
}
