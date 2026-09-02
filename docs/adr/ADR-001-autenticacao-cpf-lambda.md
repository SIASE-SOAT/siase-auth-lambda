# ADR-001 — Autenticacao de Clientes via CPF com Lambda Serverless

**Status:** Aceito
**Data:** 2026
**Repositorio:** siase-auth-lambda

## Contexto

A Fase 3 exige que clientes se autentiquem usando CPF para acessar as APIs protegidas do SIASE. A autenticacao precisa ser segura, escalavel e desacoplada da aplicacao principal. O sistema ja possui autenticacao JWT para usuarios administrativos (mecanicos) via Spring Boot.

## Decisao

Implementar a autenticacao de clientes como uma **AWS Lambda Function** em Node.js 20, exposta via **AWS API Gateway HTTP API**, com um **Lambda Authorizer** para proteger as rotas da aplicacao.

## Justificativa

- **Desacoplamento:** a logica de autenticacao de clientes e separada da aplicacao principal, permitindo evolucao independente.
- **Serverless:** sem servidores para gerenciar; escala automaticamente com a demanda; custo por invocacao.
- **Node.js 20:** runtime leve e rapido para funcoes de autenticacao; sem overhead de JVM; cold start reduzido.
- **Lambda Authorizer:** o API Gateway valida o token JWT antes de encaminhar a requisicao para a aplicacao, sem que a aplicacao precise conhecer a logica de autenticacao de clientes.
- **Contrato JWT compartilhado:** o token emitido pela Lambda usa o mesmo algoritmo HS256 e o mesmo `issuer` (`siase-auth`) que a aplicacao Spring Boot ja valida, garantindo interoperabilidade.
- **Secrets Manager:** o segredo JWT e as credenciais do banco sao lidos do Secrets Manager em tempo de execucao, sem exposicao em variaveis de ambiente estaticas.

## Alternativas Consideradas

| Alternativa                        | Motivo da Rejeicao                                                        |
|------------------------------------|---------------------------------------------------------------------------|
| Autenticacao no Spring Boot        | Acoplamento; a aplicacao principal nao deveria conhecer logica de cliente |
| Amazon Cognito                     | Complexidade de configuracao; CPF nao e um identificador nativo do Cognito|
| API Gateway com JWT nativo         | Nao permite consulta ao banco para validar existencia/status do cliente   |

## Consequencias

- A Lambda de token consulta diretamente o RDS PostgreSQL via pool de conexoes (`pg` library).
- O pool e mantido em memoria entre invocacoes quentes para reduzir latencia.
- CPFs invalidos sao rejeitados antes de qualquer consulta ao banco.
- Erros internos retornam apenas `ERRO_INTERNO`, sem detalhes de conexao ou SQL.
- O Lambda Authorizer tem TTL de 300s para cache de autorizacao no API Gateway.
