# RFC-001 — Estrategia de Autenticacao e Contrato JWT

**Status:** Implementado
**Data:** 2026
**Repositorio:** siase-auth-lambda

## Resumo

Este documento descreve a estrategia de autenticacao do SIASE para clientes externos, o contrato do token JWT emitido pela Lambda e a integracao com o Lambda Authorizer do API Gateway.

## Fluxo de Autenticacao

```
Cliente          API Gateway        Lambda Token       RDS PostgreSQL    Secrets Manager
   │                  │                  │                   │                 │
   │  POST /auth/token│                  │                   │                 │
   │  { cpf: "..." }  │                  │                   │                 │
   │─────────────────►│                  │                   │                 │
   │                  │  invoca Lambda   │                   │                 │
   │                  │─────────────────►│                   │                 │
   │                  │                  │                   │                 │
   │                  │                  │ valida CPF        │                 │
   │                  │                  │ (algoritmo local) │                 │
   │                  │                  │                   │                 │
   │                  │                  │ le JWT_SECRET_ARN │                 │
   │                  │                  │ le DB_SECRET_ARN  │                 │
   │                  │                  │──────────────────────────────────── ►
   │                  │                  │◄────────────────────────────────────│
   │                  │                  │                   │                 │
   │                  │                  │ SELECT id, ativo  │                 │
   │                  │                  │ WHERE documento=? │                 │
   │                  │                  │──────────────────►│                 │
   │                  │                  │◄──────────────────│                 │
   │                  │                  │                   │                 │
   │                  │                  │ emite JWT         │                 │
   │                  │◄─────────────────│                   │                 │
   │  200 { token }   │                  │                   │                 │
   │◄─────────────────│                  │                   │                 │
```

## Fluxo de Autorizacao (Lambda Authorizer)

```
Cliente          API Gateway        Lambda Authorizer    siase-app (EKS)
   │                  │                    │                   │
   │  GET /api/ordens │                    │                   │
   │  Authorization:  │                    │                   │
   │  Bearer <token>  │                    │                   │
   │─────────────────►│                    │                   │
   │                  │  invoca Authorizer │                   │
   │                  │───────────────────►│                   │
   │                  │                    │                   │
   │                  │                    │ verifica assinatura
   │                  │                    │ verifica issuer   │
   │                  │                    │ verifica expiracao│
   │                  │                    │ verifica clienteId│
   │                  │                    │                   │
   │                  │  { isAuthorized:   │                   │
   │                  │    true, context:  │                   │
   │                  │    { sub, clienteId│                   │
   │                  │      roles } }     │                   │
   │                  │◄───────────────────│                   │
   │                  │                    │                   │
   │                  │  encaminha request │                   │
   │                  │  + contexto        │                   │
   │                  │───────────────────────────────────────►│
   │                  │                    │                   │
   │  resposta da API │                    │                   │
   │◄──────────────────────────────────────────────────────────│
```

## Contrato do Token JWT

```json
{
  "sub": "52998224725",
  "iss": "siase-auth",
  "issuer": "siase-auth",
  "exp": 1735689600,
  "iat": 1735686000,
  "roles": ["ROLE_CLIENTE"],
  "clienteId": "uuid-do-cliente",
  "status": "ATIVO"
}
```

| Campo       | Tipo     | Descricao                                                    |
|-------------|----------|--------------------------------------------------------------|
| `sub`       | string   | CPF normalizado (apenas digitos)                             |
| `iss`       | string   | Sempre `siase-auth` — identifica o emissor                   |
| `issuer`    | string   | Duplicado do `iss` para compatibilidade com a aplicacao Java |
| `exp`       | number   | Unix timestamp de expiracao (padrao: 1h apos emissao)        |
| `iat`       | number   | Unix timestamp de emissao                                    |
| `roles`     | string[] | Sempre `["ROLE_CLIENTE"]` para tokens de cliente             |
| `clienteId` | string   | UUID do cliente na base de dados                             |
| `status`    | string   | Sempre `ATIVO` (clientes inativos nao recebem token)         |

## Respostas da Lambda de Token

| Situacao                              | HTTP | Codigo                  |
|---------------------------------------|------|-------------------------|
| CPF invalido, repetido ou tamanho errado | 400 | `CPF_INVALIDO`        |
| CPF valido, cliente nao encontrado    | 404  | `CLIENTE_NAO_ENCONTRADO`|
| Cliente encontrado, mas inativo       | 403  | `CLIENTE_INATIVO`       |
| Cliente ativo                         | 200  | JWT Bearer              |
| Erro interno                          | 500  | `ERRO_INTERNO`          |

## Seguranca

- CPFs invalidos sao rejeitados antes de qualquer consulta ao banco (validacao dos dois digitos verificadores).
- Erros internos retornam apenas `ERRO_INTERNO`, sem detalhes de conexao, SQL ou stack trace.
- O segredo JWT e lido do Secrets Manager e mantido em cache na memoria da execucao Lambda (warm instance).
- O pool de conexoes PostgreSQL e reutilizado entre invocacoes quentes (max 2 conexoes por instancia).
- A conexao com o RDS usa SSL com o certificado `global-bundle.pem` da AWS (`rejectUnauthorized: true`).
- O Lambda Authorizer tem TTL de 300s para cache de autorizacao, reduzindo invocacoes e latencia.
