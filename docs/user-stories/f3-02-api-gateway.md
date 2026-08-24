# US-F3-02: API Gateway e Protecao de Rotas Sensiveis

**User Story:** Como Gestor, quero um API Gateway na frente da aplicacao roteando e protegendo as rotas sensiveis via autenticacao por CPF, para centralizar controle de acesso, throttling e observabilidade de borda.

**Prioridade:** Alta
**Story Points:** 5
**Status:** To Do
**DDD Domain:** Autenticacao / Infraestrutura de borda
**DDD Layer:** Infrastructure
**Repositorio:** 1/2 — gateway provisionado por Terraform (junto ao repo da Lambda ou do cluster)

## Criterios de Aceite

- [ ] **AWS API Gateway** provisionado por Terraform como ponto de entrada unico das APIs
- [ ] Rota publica de **autenticacao** (`/auth`) integrada a **Lambda** de CPF ([f3-01](f3-01-serverless-cpf-auth.md))
- [ ] **Rotas sensiveis** da aplicacao protegidas — exigem JWT valido emitido pela Lambda
- [ ] Mecanismo de protecao definido: **Lambda Authorizer** (ou JWT Authorizer nativo) validando o token antes de encaminhar ao backend no EKS
- [ ] Rotas publicas explicitamente liberadas (ex.: consulta de status de OS pelo cliente, `/health`)
- [ ] **Throttling / rate limiting** configurado no gateway
- [ ] Roteamento do gateway para o **Service/Ingress do EKS** (ver [f3-06](f3-06-deploy-aplicacao-eks.md))
- [ ] CORS configurado para as UIs (admin/cliente)
- [ ] Logs de acesso do gateway habilitados e exportados para observabilidade ([f3-10](f3-10-observabilidade-apm.md))
- [ ] Diagrama de sequencia do fluxo `cliente -> API Gateway -> Lambda -> JWT -> API protegida` ([f3-doc-03](f3-doc-03-arquitetura-diagramas.md))
- [ ] Documentado no README com a URL publica do gateway

## Notas

- Alternativas avaliadas na RFC de arquitetura: **Kong** / **Traefik** (in-cluster). Escolha AWS API Gateway registrada em ADR ([f3-doc-02](f3-doc-02-adrs.md)).
