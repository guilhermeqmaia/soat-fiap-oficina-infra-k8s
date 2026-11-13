# Stage cluster — VPC endpoints.
#
# DynamoDB e um servico REGIONAL: nao existe "instancia dentro da subnet" como
# no RDS (que e uma instancia com ENI na subnet privada). A unica forma de a
# VPC "entrar" no DynamoDB sem passar pela internet e um VPC Gateway Endpoint:
# uma rota-prefixo (pl-xxxx do servico) injetada nas route tables privadas,
# fazendo o trafego dos nodes do EKS ir direto a rede da AWS em vez de sair
# pelo NAT Gateway para o endpoint publico.
#
#   - Tipo Gateway: SEM custo por hora nem por GB (ao contrario do Interface
#     Endpoint/PrivateLink) e ainda economiza o trafego cobrado do NAT.
#   - A `policy` do endpoint limita O QUE a VPC alcanca: so as 4 tabelas da
#     Execucao (repo infra-db: `<prefixo>execucoes`, `<prefixo>servicos`,
#     `<prefixo>produtos`, `<prefixo>movimentacoes_estoque`) e seus indices,
#     so com as acoes de dados. O prefixo (`dynamodb_table_prefix`) e o mesmo
#     do infra-db e do `DYNAMODB_TABLE_PREFIX` do execucao-service.
#     Quem pode fazer cada acao continua sendo decidido pela policy IAM da
#     role dos nodes — endpoint policy e IAM se somam (ambas precisam permitir).
#   - Decisao do time (04/11/2026): o Execucao Service so fala com o DynamoDB
#     por dentro da VPC, sem NAT, com politica restrita as suas tabelas.
#
# Obs.: so as route tables PRIVADAS recebem a rota — e onde vivem os nodes.
# O CI (GitHub Actions) acessa a tabela de lock do state de fora da VPC e nao
# e afetado por esta policy.

data "aws_caller_identity" "current" {}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  route_table_ids   = [aws_route_table.private.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ExecucaoTablesOnly"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:TransactGetItems",
          "dynamodb:TransactWriteItems",
          "dynamodb:DescribeTable",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = [
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_prefix}*",
          "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_table_prefix}*/index/*",
        ]
      }
    ]
  })

  tags = { Name = "${var.project_name}-dynamodb" }
}
