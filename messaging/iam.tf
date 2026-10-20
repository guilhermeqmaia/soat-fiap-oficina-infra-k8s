# Stage messaging — permissao dos servicos no EKS.
#
# Sem IRSA (decisao do stage cluster: funciona no Academy e na conta propria),
# os pods herdam a role dos NODES. A policy abaixo libera publicar nos 3
# topicos e consumir as 4 filas (+ DLQs, para reprocessamento). A separacao
# "cada servico so publica no seu topico" fica garantida pelo kit (cada
# servico recebe apenas o SEU topic ARN e a SUA queue URL via ConfigMap).
data "aws_iam_policy_document" "services" {
  statement {
    sid       = "PublishTopics"
    effect    = "Allow"
    actions   = ["sns:Publish", "sns:GetTopicAttributes"]
    resources = [for t in aws_sns_topic.this : t.arn]
  }

  statement {
    sid    = "ConsumeQueues"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage", # reprocessamento manual da DLQ -> fila principal
    ]
    resources = concat([for q in aws_sqs_queue.this : q.arn], [for q in aws_sqs_queue.dlq : q.arn])
  }
}

resource "aws_iam_policy" "services" {
  name        = "${var.project_name}-messaging-services"
  description = "Publicar nos topicos e consumir as filas da mensageria da oficina (RFC-0006)."
  policy      = data.aws_iam_policy_document.services.json
}

resource "aws_iam_role_policy_attachment" "nodes" {
  count = var.node_role_name != "" ? 1 : 0

  role       = var.node_role_name
  policy_arn = aws_iam_policy.services.arn
}
