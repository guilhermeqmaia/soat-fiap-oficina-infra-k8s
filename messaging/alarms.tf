# Stage messaging — alarme por DLQ (ADR-0009: mensagem na DLQ exige triagem humana).
#
# CloudWatch e a fonte; o Datadog (stage observability) tambem le a metrica
# via integracao AWS. O e-mail e opcional (alert_email).
resource "aws_sns_topic" "alerts" {
  count = var.alert_email != "" ? 1 : 0
  name  = "${var.name_prefix}-messaging-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  for_each = local.queues

  alarm_name          = "${each.value}-dlq-nao-vazia"
  alarm_description   = "Mensagens na DLQ ${each.value}-dlq (consumidor: ${local.queue_owner[each.key]}). Runbook: README do stage messaging > Reprocessar a DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq[each.key].name
  }

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []
  ok_actions    = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []
}
