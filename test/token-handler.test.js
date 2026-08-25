import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { createTokenHandler, resetPool } from '../src/token-handler.js';

const cpf = '52998224725';
const secret = { secret: Buffer.alloc(32, 65).toString('base64') };

function event(body, headers = {}) {
  return { body: JSON.stringify(body), headers };
}

function setup(rows) {
  resetPool();
  const pool = { query: async () => ({ rows }) };
  const handler = createTokenHandler({
    getSecretValue: async arn => arn === 'jwt' ? secret : {
      username: 'rds-master', password: 'test'
    },
    poolFactory: () => pool
  });
  process.env.JWT_SECRET_ARN = 'jwt';
  process.env.DB_SECRET_ARN = 'db';
  process.env.DB_HOST = 'rds.example.internal';
  process.env.DB_NAME = 'siase';
  process.env.JWT_ISSUER = 'siase-auth';
  return handler;
}

test('retorna CPF_INVALIDO para CPF inválido', async () => {
  const result = await setup([])(event({ cpf: '11111111111' }));
  assert.equal(result.statusCode, 400);
  assert.deepEqual(JSON.parse(result.body), { error: 'CPF_INVALIDO' });
});

test('retorna 400 para corpo JSON malformado', async () => {
  const result = await setup([])({ body: '{"cpf":', headers: {} });
  assert.equal(result.statusCode, 400);
  assert.deepEqual(JSON.parse(result.body), { error: 'REQUISICAO_INVALIDA' });
});

test('retorna 400 quando o CPF não foi informado', async () => {
  const result = await setup([])(event({}));
  assert.equal(result.statusCode, 400);
  assert.deepEqual(JSON.parse(result.body), { error: 'CPF_INVALIDO' });
});

test('retorna CLIENTE_NAO_ENCONTRADO sem revelar detalhes do banco', async () => {
  const result = await setup([])(event({ cpf }));
  assert.equal(result.statusCode, 404);
  assert.deepEqual(JSON.parse(result.body), { error: 'CLIENTE_NAO_ENCONTRADO' });
});

test('retorna CLIENTE_INATIVO', async () => {
  const result = await setup([{ id: 'client-1', ativo: false }])(event({ cpf }));
  assert.equal(result.statusCode, 403);
  assert.deepEqual(JSON.parse(result.body), { error: 'CLIENTE_INATIVO' });
});

test('emite token com os claims externos do contrato', async () => {
  const result = await setup([{ id: 'client-1', ativo: true }])(event(
    { cpf: `529.982.247-25` },
    { 'x-correlation-id': 'corr-1' }
  ));
  assert.equal(result.statusCode, 200);
  assert.equal(result.headers['X-Correlation-Id'], 'corr-1');
  const payload = jwt.verify(JSON.parse(result.body).token, Buffer.from(secret.secret, 'base64'), {
    issuer: 'siase-auth',
    algorithms: ['HS256']
  });
  assert.equal(payload.sub, cpf);
  assert.equal(payload.iss, 'siase-auth');
  assert.equal(payload.clienteId, 'client-1');
  assert.equal(payload.status, 'ATIVO');
  assert.deepEqual(payload.roles, ['ROLE_CLIENTE']);
});

test('combina credenciais do segredo RDS com host e nome vindos do ambiente', async () => {
  resetPool();
  let poolConfig;
  const handler = createTokenHandler({
    getSecretValue: async arn => arn === 'jwt' ? secret : {
      username: 'rds-master',
      password: 'master-password'
    },
    poolFactory: config => {
      poolConfig = config;
      return { query: async () => ({ rows: [] }) };
    }
  });
  process.env.JWT_SECRET_ARN = 'jwt';
  process.env.DB_SECRET_ARN = 'db';
  process.env.DB_HOST = 'rds.example.internal';
  process.env.DB_NAME = 'siase';
  process.env.JWT_ISSUER = 'siase-auth';

  const result = await handler(event({ cpf }));

  assert.equal(result.statusCode, 404);
  assert.equal(poolConfig.host, 'rds.example.internal');
  assert.equal(poolConfig.port, 5432);
  assert.equal(poolConfig.database, 'siase');
  assert.equal(poolConfig.user, 'rds-master');
  assert.equal(poolConfig.password, 'master-password');
});
