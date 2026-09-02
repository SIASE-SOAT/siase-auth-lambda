# Diagramas de Sequencia — siase-auth-lambda

## 1. Autenticacao de Cliente via CPF (POST /auth/token)

```
Cliente          API Gateway        Lambda Token       RDS PostgreSQL    Secrets Manager
   │                  │                  │                   │                 │
   │  POST /auth/token│                  │                   │                 │
   │  { "cpf": "529.982.247-25" }        │                   │                 │
   │─────────────────►│                  │                   │                 │
   │                  │                  │                   │                 │
   │                  │  invoca Lambda   │                   │                 │
   │                  │  (rota publica)  │                   │                 │
   │                  │─────────────────►│                   │                 │
   │                  │                  │                   │                 │
   │                  │                  │ normaliza CPF     │                 │
   │                  │                  │ (remove pontos    │                 │
   │                  │                  │  e traco)         │                 │
   │                  │                  │                   │                 │
   │                  │                  │ valida digitos    │                 │
   │                  │                  │ verificadores     │                 │
   │                  │                  │                   │                 │
   │                  │                  │ [CPF invalido]    │                 │
   │                  │◄─────────────────│ 400 CPF_INVALIDO  │                 │
   │◄─────────────────│                  │                   │                 │
   │                  │                  │                   │                 │
   │                  │                  │ [CPF valido]      │                 │
   │                  │                  │ le JWT_SECRET_ARN │                 │
   │                  │                  │ le DB_SECRET_ARN  │                 │
   │                  │                  │ (cache warm)      │                 │
   │                  │                  │─────────────────────────────────── ►│
   │                  │                  │◄────────────────────────────────────│
   │                  │                  │                   │                 │
   │                  │                  │ SELECT id, ativo  │                 │
   │                  │                  │ FROM clientes     │                 │
   │                  │                  │ WHERE documento=? │                 │
   │                  │                  │ (SSL + pool)      │                 │
   │                  │                  │──────────────────►│                 │
   │                  │                  │◄──────────────────│                 │
   │                  │                  │                   │                 │
   │                  │                  │ [nao encontrado]  │                 │
   │                  │◄─────────────────│ 404 CLIENTE_NAO_  │                 │
   │◄─────────────────│                  │ ENCONTRADO        │                 │
   │                  │                  │                   │                 │
   │                  │                  │ [inativo]         │                 │
   │                  │◄─────────────────│ 403 CLIENTE_INATIVO                 │
   │◄─────────────────│                  │                   │                 │
   │                  │                  │                   │                 │
   │                  │                  │ [ativo]           │                 │
   │                  │                  │ assina JWT HS256  │                 │
   │                  │                  │ { sub, iss,       │                 │
   │                  │                  │   clienteId,      │                 │
   │                  │                  │   roles, status } │                 │
   │                  │◄─────────────────│                   │                 │
   │  200 { token,    │                  │                   │                 │
   │  tokenType,      │                  │                   │                 │
   │  expiresIn }     │                  │                   │                 │
   │◄─────────────────│                  │                   │                 │
```

## 2. Autorizacao de Requisicao (Lambda Authorizer)

```
Cliente          API Gateway        Lambda Authorizer    Secrets Manager    siase-app
   │                  │                    │                   │                │
   │  GET /api/ordens │                    │                   │                │
   │  Authorization:  │                    │                   │                │
   │  Bearer <jwt>    │                    │                   │                │
   │─────────────────►│                    │                   │                │
   │                  │                    │                   │                │
   │                  │ [cache miss]       │                   │                │
   │                  │ invoca Authorizer  │                   │                │
   │                  │───────────────────►│                   │                │
   │                  │                    │                   │                │
   │                  │                    │ extrai Bearer     │                │
   │                  │                    │ token do header   │                │
   │                  │                    │                   │                │
   │                  │                    │ [token ausente]   │                │
   │                  │◄───────────────────│ { isAuthorized:   │                │
   │  401             │                    │   false }         │                │
   │◄─────────────────│                    │                   │                │
   │                  │                    │                   │                │
   │                  │                    │ [token presente]  │                │
   │                  │                    │ le JWT_SECRET_ARN │                │
   │                  │                    │ (cache warm)      │                │
   │                  │                    │──────────────────►│                │
   │                  │                    │◄──────────────────│                │
   │                  │                    │                   │                │
   │                  │                    │ verifica assinatura HS256          │
   │                  │                    │ verifica issuer = "siase-auth"     │
   │                  │                    │ verifica expiracao                 │
   │                  │                    │ verifica clienteId presente        │
   │                  │                    │                   │                │
   │                  │                    │ [invalido/expirado]│               │
   │                  │◄───────────────────│ { isAuthorized: false }            │
   │  403             │                    │                   │                │
   │◄─────────────────│                    │                   │                │
   │                  │                    │                   │                │
   │                  │                    │ [valido]          │                │
   │                  │◄───────────────────│ { isAuthorized: true,              │
   │                  │                    │   context: { sub, │                │
   │                  │                    │   clienteId,      │                │
   │                  │                    │   roles } }       │                │
   │                  │                    │                   │                │
   │                  │ [cache: 300s]      │                   │                │
   │                  │ encaminha request  │                   │                │
   │                  │ + contexto JWT     │                   │                │
   │                  │─────────────────────────────────────────────────────── ►│
   │                  │                    │                   │                │
   │  resposta da API │                    │                   │                │
   │◄───────────────────────────────────────────────────────────────────────────│
```

## 3. Notificacao Assincrona via SNS

```
siase-app        SNS Topic          Lambda Notification    DLQ (SQS)
    │                │                      │                  │
    │  Publish       │                      │                  │
    │  { clienteId,  │                      │                  │
    │    subject,    │                      │                  │
    │    correlationId}                     │                  │
    │───────────────►│                      │                  │
    │                │                      │                  │
    │                │  invoca Lambda       │                  │
    │                │─────────────────────►│                  │
    │                │                      │                  │
    │                │                      │ parse JSON       │
    │                │                      │ valida clienteId │
    │                │                      │ e subject        │
    │                │                      │                  │
    │                │                      │ [invalido]       │
    │                │                      │ lanca erro       │
    │                │                      │─────────────────►│
    │                │                      │                  │
    │                │                      │ [valido]         │
    │                │                      │ log JSON:        │
    │                │                      │ { correlationId, │
    │                │                      │   clienteId,     │
    │                │                      │   subject,       │
    │                │                      │   notification } │
    │                │                      │                  │
    │                │◄─────────────────────│                  │
    │                │  { processed: N }    │                  │
```

## 4. Deploy via CI/CD

```
Developer        GitHub PR          CI Workflow        AWS (OIDC)         Lambda/API GW
    │                │                   │                  │                   │
    │  push branch   │                   │                  │                   │
    │───────────────►│                   │                  │                   │
    │                │                   │                  │                   │
    │                │  PR → main        │                  │                   │
    │                │──────────────────►│                  │                   │
    │                │                   │                  │                   │
    │                │                   │ npm ci           │                   │
    │                │                   │ node --test      │                   │
    │                │                   │ tf fmt -check    │                   │
    │                │                   │ tf validate      │                   │
    │                │                   │                  │                   │
    │  merge → main  │                   │                  │                   │
    │───────────────►│                   │                  │                   │
    │                │                   │                  │                   │
    │                │  deploy-prod.yml  │                  │                   │
    │                │──────────────────►│                  │                   │
    │                │                   │                  │                   │
    │                │                   │ OIDC token       │                   │
    │                │                   │─────────────────►│                   │
    │                │                   │◄─────────────────│                   │
    │                │                   │                  │                   │
    │                │                   │ terraform apply  │                   │
    │                │                   │─────────────────────────────────────►│
    │                │                   │◄─────────────────────────────────────│
    │                │                   │                  │                   │
    │  deploy ok     │                   │                  │                   │
    │◄───────────────│                   │                  │                   │
```
