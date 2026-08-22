# SIASE Auth Lambda

Siase: Autenticação de clientes por CPF, Lambda Authorizer para o
API Gateway HTTP API e notificação assíncrona por SNS. O runtime das funções é
Node.js 20, sem framework HTTP.


## Arquitetura

O token usa o contrato compartilhado com `siase-app`:

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

## Funções

### `POST /auth/token`

Recebe:

```json
{ "cpf": "529.982.247-25" }
```

O CPF é normalizado, validado pelos dois dígitos verificadores e consultado na
coluna `clientes.documento` do RDS. As respostas são distintas:

| Situação | HTTP | Código |
| --- | ---: | --- |
| CPF inválido, repetido ou com tamanho incorreto | 400 | `CPF_INVALIDO` |
| CPF válido sem cliente | 404 | `CLIENTE_NAO_ENCONTRADO` |
| Cliente encontrado, mas inativo | 403 | `CLIENTE_INATIVO` |
| Cliente ativo | 200 | JWT Bearer |

Nenhuma consulta ao banco acontece para CPF inválido. Erros internos retornam
somente `ERRO_INTERNO`, sem detalhes de conexão ou SQL.

### Lambda Authorizer

É um authorizer REQUEST para payload v2 e respostas simples. Verifica:

- assinatura HS256;
- `issuer`;
- expiração;
- presença de `clienteId`, que caracteriza o token externo emitido por esta
  etapa.

O contexto simples contém `sub`, `clienteId` e `roles`. Como o contexto simples
do API Gateway usa valores escalares, `roles` é enviado como uma string separada
por vírgulas.

### Lambda de notificação

Consome registros SNS, formata a mensagem para o cliente e registra JSON com
`correlationId`, `clienteId`, `subject` e `notification`. Mensagens inválidas
lançam erro para que o SNS possa encaminhar a falha à DLQ. O envio real por
e-mail/SMS não faz parte desta etapa.

## Como rodar localmente

Requisitos:

- Node.js 20;
- npm;
- PostgreSQL acessível se for executar a Lambda de token sem mock;
- valores locais dos segredos, nunca commitados.

Instale exatamente as versões do lockfile:

```bash
npm ci
```

Execute os testes:

```bash
node --test
```

Para executar a função diretamente, importe o handler em um runner local ou use
um emulador de Lambda. As variáveis necessárias são:

```bash
export JWT_SECRET_ARN=arn:aws:secretsmanager:REGION:ACCOUNT:secret:siase/homolog/jwt
export DB_SECRET_ARN=arn:aws:secretsmanager:REGION:ACCOUNT:secret:siase/homolog/database
export JWT_ISSUER=siase-auth
export JWT_EXPIRATION=1h
```

O segredo JWT deve ser JSON com a chave `secret`:

```json
{ "secret": "valor-base64-com-pelo-menos-32-bytes" }
```

O segredo do banco deve conter pelo menos:

```json
{
  "host": "endpoint-do-rds",
  "port": 5432,
  "database": "siase_db",
  "username": "siase",
  "password": "FORA_DO_GIT"
}
```

Os segredos são lidos pelo Secrets Manager e mantidos em cache na memória da
execução Lambda. Uma nova instância fria faz nova leitura.

## Infraestrutura Terraform

O diretório `infra/` cria:

- três Lambdas Node.js 20;
- roles IAM separadas;
- permissão mínima de `secretsmanager:GetSecretValue`;
- VPC configuration das três Lambdas nas subnets privadas; a VPC precisa de
  NAT ou endpoints privados para os serviços AWS usados pelas funções;
- API Gateway HTTP API;
- rota pública `POST /auth/token`;
- rota `ANY /{proxy+}` protegida pelo Lambda Authorizer;
- integração HTTP com o DNS do ALB;
- tópico SNS, assinatura da Lambda de notificação e fila SQS de DLQ;
- segredos do Secrets Manager sem valor inicial.


O recurso `aws_secretsmanager_secret` cria o nome/ARN, mas não grava o valor no
código. A versão/valor não é gerenciada pelo Terraform: isso evita que um
`apply` sobrescreva a versão definida operacionalmente e tem o mesmo efeito
prático de ignorar alterações de versão.

- `aws_region`;
- `environment` (`homolog` ou `production`);
- `vpc_id`;
- `private_subnet_ids`;
- `lambda_security_group_id`;
- nomes dos segredos;
- bucket S3 e tabela DynamoDB do state;
- parâmetro SSM do ALB ou `alb_dns_override`.

## CI/CD com OIDC

Os workflows são:

- `build-test.yml`: reutilizável via `workflow_call`;
- `ci.yml`: pull requests para `main` e `develop`;
- `deploy-homolog.yml`: push na `develop`;
- `deploy-prod.yml`: push na `main`.

O deploy depende de `needs: build-test`. A AWS é acessada com OIDC e
`id-token: write`; não há chave AWS estática, PAT, senha ou SSH.

Crie no GitHub os Environments `homolog` e `production`. Em cada um, crie:

| Tipo | Nome | Descrição |
| --- | --- | --- |
| Variable | `AWS_REGION` | Região AWS |
| Variable | `TF_STATE_BUCKET` | Bucket S3 do state |
| Variable | `TF_LOCK_TABLE` | Tabela DynamoDB de lock |
| Variable | `VPC_ID` | VPC do ambiente |
| Variable | `PRIVATE_SUBNET_IDS` | IDs separados por vírgula; o workflow converte para lista Terraform |
| Variable | `LAMBDA_SECURITY_GROUP_ID` | SG da Lambda de token |
| Variable | `DB_SECRET_NAME` | Nome do segredo de banco |
| Variable | `JWT_SECRET_NAME` | Nome do segredo JWT |
| Variable | `ALB_DNS_OVERRIDE` | Opcional; vazio usa SSM |
| Secret | `AWS_DEPLOY_ROLE_ARN` | ARN da role confiável para OIDC |


## API, OpenAPI e Postman

- Especificação: [`docs/openapi.yaml`](docs/openapi.yaml)
- Collection: [`docs/postman/siase-auth.postman_collection.json`](docs/postman/siase-auth.postman_collection.json)



## Verificações locais

```bash
npm ci
node --test
terraform -chdir=infra fmt -check
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
```

O teste `test/token-handler.test.js` cobre CPF inválido, cliente inexistente,
cliente inativo e sucesso, incluindo a decodificação e validação dos claims do
JWT.
