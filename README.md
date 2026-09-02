# siase-auth-lambda

> Pos Tech - Software Architecture | FIAP | Fase 3 — Autenticacao Serverless e API Gateway

## Descricao da Solucao

Repositorio responsavel pela autenticacao de clientes do SIASE via CPF, pelo Lambda Authorizer do API Gateway e pelas notificacoes assincronas via SNS. O runtime das funcoes e Node.js 20, sem framework HTTP, com foco em seguranca, baixa latencia e custo por invocacao.

## Tecnologias

| Tecnologia              | Versao  | Justificativa                                                                 |
|-------------------------|---------|-------------------------------------------------------------------------------|
| Node.js                 | 20      | Runtime leve, cold start reduzido, ideal para funcoes de autenticacao         |
| AWS Lambda              | —       | Serverless — escala automaticamente, custo por invocacao, sem servidores      |
| AWS API Gateway HTTP API| —       | Roteamento, autorizacao e integracao com Lambda e ALB                         |
| AWS Secrets Manager     | —       | Armazenamento seguro do segredo JWT e credenciais do banco                    |
| AWS SNS + SQS (DLQ)     | —       | Notificacoes assincronas com fila de mensagens mortas                         |
| PostgreSQL (RDS)        | 16      | Consulta de existencia e status do cliente via pool de conexoes               |
| Terraform               | 1.7+    | Provisionamento declarativo de toda a infraestrutura serverless               |
| GitHub Actions (OIDC)   | —       | CI/CD sem chaves de acesso estaticas                                          |

## Arquitetura

```
                        Internet
                            │
                            ▼
                   ┌─────────────────┐
                   │   API Gateway   │
                   │   HTTP API      │
                   └────────┬────────┘
                            │
              ┌─────────────┼──────────────────┐
              │             │                  │
              ▼             ▼                  ▼
    POST /auth/token   ANY /{proxy+}      (Authorizer)
              │        (protegida)             │
              ▼             │                  │
    ┌──────────────┐        │        ┌─────────────────────┐
    │ Lambda Token │        │        │  Lambda Authorizer  │
    │              │        │        │  verifica JWT HS256 │
    │ valida CPF   │        │        │  issuer, exp,       │
    │ consulta RDS │        │        │  clienteId          │
    │ emite JWT    │        │        └─────────────────────┘
    └──────┬───────┘        │
           │                ▼
           │      ┌──────────────────┐
           │      │  siase-app (EKS) │
           │      │  via ALB         │
           │      └──────────────────┘
           │
           ▼
    ┌──────────────────┐    ┌──────────────────┐
    │  RDS PostgreSQL  │    │  Secrets Manager │
    │  (subnet privada)│    │  JWT + DB creds  │
    └──────────────────┘    └──────────────────┘

    ┌──────────────────────────────────────────┐
    │  SNS Topic → Lambda Notification → DLQ   │
    │  (notificacoes assincronas de clientes)  │
    └──────────────────────────────────────────┘
```

## Funcoes Lambda

### `POST /auth/token` — Lambda de Token

Recebe o CPF do cliente, valida, consulta o RDS e emite um JWT.

**Request:**
```json
{ "cpf": "529.982.247-25" }
```

**Respostas:**

| Situacao                                    | HTTP | Codigo                   |
|---------------------------------------------|------|--------------------------|
| CPF invalido, repetido ou tamanho incorreto | 400  | `CPF_INVALIDO`           |
| CPF valido, cliente nao encontrado          | 404  | `CLIENTE_NAO_ENCONTRADO` |
| Cliente encontrado, mas inativo             | 403  | `CLIENTE_INATIVO`        |
| Cliente ativo                               | 200  | JWT Bearer               |
| Erro interno                                | 500  | `ERRO_INTERNO`           |

**Token emitido:**
```json
{
  "sub": "52998224725",
  "iss": "siase-auth",
  "issuer": "siase-auth",
  "exp": 1735689600,
  "roles": ["ROLE_CLIENTE"],
  "clienteId": "uuid-do-cliente",
  "status": "ATIVO"
}
```

### Lambda Authorizer

Authorizer REQUEST para payload v2 com respostas simples. Verifica:
- Assinatura HS256
- `issuer` = `siase-auth`
- Expiracao
- Presenca de `clienteId` (caracteriza token de cliente externo)

O contexto retornado ao API Gateway contem `sub`, `clienteId` e `roles` (string separada por virgulas).

### Lambda de Notificacao

Consome registros SNS, valida `clienteId` e `subject`, formata e registra a notificacao em JSON estruturado com `correlationId`. Mensagens invalidas lancam erro para encaminhamento a DLQ.

## Recursos Criados pelo Terraform

| Recurso                          | Tipo                    | Descricao                                              |
|----------------------------------|-------------------------|--------------------------------------------------------|
| `aws_lambda_function.token`      | Lambda Node.js 20       | Autenticacao de clientes via CPF                       |
| `aws_lambda_function.authorizer` | Lambda Node.js 20       | Validacao de JWT para rotas protegidas                 |
| `aws_lambda_function.notification`| Lambda Node.js 20      | Processamento de notificacoes SNS                      |
| `aws_apigatewayv2_api.http`      | API Gateway HTTP API    | Ponto de entrada unico da aplicacao                    |
| `aws_apigatewayv2_authorizer`    | Lambda Authorizer       | Protege `ANY /{proxy+}` com JWT                        |
| `aws_apigatewayv2_route.token`   | Rota publica            | `POST /auth/token` sem autorizacao                     |
| `aws_apigatewayv2_route.application` | Rota protegida      | `ANY /{proxy+}` com Lambda Authorizer                  |
| `aws_sns_topic.notification`     | SNS Topic               | Topico de notificacoes de clientes                     |
| `aws_sqs_queue.notification_dlq` | SQS Queue               | Fila de mensagens mortas para falhas de notificacao    |
| `aws_ssm_parameter.api_endpoint` | SSM Parameter           | Endpoint do API Gateway publicado para outros servicos |

## Variaveis Terraform

| Variavel                  | Padrao       | Descricao                                              |
|---------------------------|--------------|--------------------------------------------------------|
| `aws_region`              | —            | Regiao AWS (obrigatoria)                               |
| `environment`             | `production` | Ambiente                                               |
| `vpc_id`                  | —            | VPC onde a Lambda acessa o RDS                         |
| `private_subnet_ids`      | —            | Subnets privadas para a Lambda de token                |
| `lambda_security_group_id`| —            | SG com acesso de saida ao RDS                          |
| `lab_role_arn`            | —            | ARN da LabRole do AWS Academy                          |
| `jwt_secret_name`         | —            | Nome do segredo JWT no Secrets Manager                 |
| `jwt_issuer`              | `siase-auth` | Issuer do JWT                                          |
| `jwt_expiration`          | `1h`         | Tempo de expiracao do token                            |
| `lambda_memory_size`      | `256`        | Memoria das Lambdas em MB                              |
| `lambda_timeout`          | `10`         | Timeout das Lambdas em segundos                        |

## Como Rodar Localmente

**Pre-requisitos:** Node.js 20, npm.

```bash
# Instalar dependencias (versoes exatas do lockfile)
npm ci

# Executar testes
node --test
```

**Variaveis necessarias para execucao sem mock:**
```bash
export JWT_SECRET_ARN=arn:aws:secretsmanager:REGION:ACCOUNT:secret:siase/production/jwt
export DB_SECRET_ARN=arn:aws:secretsmanager:REGION:ACCOUNT:secret:siase/production/database
export JWT_ISSUER=siase-auth
export JWT_EXPIRATION=1h
```

**Formato do segredo JWT:**
```json
{ "secret": "valor-base64-com-pelo-menos-32-bytes" }
```

**Formato do segredo do banco:**
```json
{
  "host": "endpoint-do-rds",
  "port": 5432,
  "database": "siase_db",
  "username": "siase_master",
  "password": "FORA_DO_GIT"
}
```

## Deploy e Infraestrutura

### Pre-requisitos

- Terraform 1.7+
- `siase-infra-k8s` ja aplicado (publica VPC, subnets e SG via SSM)
- `siase-infra-database` ja aplicado (publica endpoint e ARN do segredo do banco via SSM)
- Segredo JWT criado manualmente no Secrets Manager

### Aplicar

```bash
# 1. Copiar e ajustar variaveis
cp infra/environments/production.tfvars.example infra/environments/production.tfvars

# 2. Inicializar backend
terraform -chdir=infra init

# 3. Visualizar plano
terraform -chdir=infra plan -var-file=environments/production.tfvars

# 4. Aplicar
terraform -chdir=infra apply -var-file=environments/production.tfvars
```

### Validacao local

```bash
npm ci
node --test
terraform -chdir=infra fmt -check
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
```

## CI/CD

| Workflow           | Gatilho                        | O que faz                                                    |
|--------------------|--------------------------------|--------------------------------------------------------------|
| `build-test.yml`   | Reutilizavel via workflow_call | `npm ci`, `node --test`, `tf fmt -check`, `tf validate`      |
| `ci.yml`           | Pull Request para main/develop | Chama build-test                                             |
| `deploy-prod.yml`  | Push na main                   | `npm ci`, `terraform apply` com credenciais temporarias do Learner Lab |

**Observacao sobre autenticacao AWS:** o Learner Lab nao suporta OIDC. O workflow usa credenciais temporarias (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) que expiram a cada sessao de 4h e precisam ser atualizadas manualmente nos secrets do GitHub.

O `deploy-prod.yml` passa as variaveis Terraform via `TF_VAR_*` e converte `PRIVATE_SUBNET_IDS` de CSV para lista JSON antes do apply.

**GitHub Variables necessarias (Environment `production`):**

| Nome                          | Descricao                              |
|-------------------------------|----------------------------------------|
| `AWS_REGION`                  | Regiao AWS                             |
| `TF_STATE_BUCKET`             | Bucket S3 do estado Terraform          |
| `VPC_ID`                      | VPC do ambiente                        |
| `PRIVATE_SUBNET_IDS`          | IDs das subnets privadas separados por virgula |
| `LAMBDA_SECURITY_GROUP_ID`    | SG da Lambda de token                  |
| `JWT_SECRET_NAME`             | Nome do segredo JWT no Secrets Manager |
| `LAB_ROLE_ARN`                | ARN da LabRole do AWS Academy          |
| `LB_DNS_OVERRIDE`             | Opcional; vazio usa SSM                |

**GitHub Secrets necessarios:**

| Nome                    | Descricao                                      |
|-------------------------|------------------------------------------------|
| `AWS_ACCESS_KEY_ID`     | Chave de acesso temporaria do Learner Lab       |
| `AWS_SECRET_ACCESS_KEY` | Chave secreta temporaria do Learner Lab         |
| `AWS_SESSION_TOKEN`     | Token de sessao temporario do Learner Lab       |

## Documentacao

- [Diagramas de Sequencia](docs/diagramas-sequencia.md)
- [ADR-001 — Autenticacao de Clientes via CPF com Lambda Serverless](docs/adr/ADR-001-autenticacao-cpf-lambda.md)
- [ADR-002 — Escolha da AWS como Provedor de Nuvem](docs/adr/ADR-002-escolha-aws.md)
- [RFC-001 — Estrategia de Autenticacao e Contrato JWT](docs/rfc/RFC-001-estrategia-autenticacao.md)
- [OpenAPI](docs/openapi.yaml)
- [Postman Collection](docs/postman/siase-auth.postman_collection.json)
