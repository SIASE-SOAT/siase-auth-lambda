import { Pool } from 'pg';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { isValidCpf, normalizeCpf } from './cpf.js';
import { correlationIdFromEvent, log } from './log.js';
import { getSecret } from './secrets.js';
import { issueClientToken } from './token-service.js';

let pool;

export function createTokenHandler({ getSecretValue = getSecret, poolFactory = createPool } = {}) {
  return async function handler(event) {
    const correlationId = correlationIdFromEvent(event);
    try {
      const body = parseBody(event);
      const cpf = normalizeCpf(body.cpf);
      if (!isValidCpf(cpf)) {
        return response(400, 'CPF_INVALIDO', correlationId);
      }

      const [jwtConfig, dbConfig] = await Promise.all([
        getSecretValue(process.env.JWT_SECRET_ARN),
        getSecretValue(process.env.DB_SECRET_ARN)
      ]);
      const clientPool = pool ??= poolFactory(databaseConfig(dbConfig));
      const result = await clientPool.query(
        'SELECT id, ativo FROM clientes WHERE documento = $1',
        [cpf]
      );
      const cliente = result.rows[0];
      if (!cliente) {
        return response(404, 'CLIENTE_NAO_ENCONTRADO', correlationId);
      }
      if (cliente.ativo !== true) {
        return response(403, 'CLIENTE_INATIVO', correlationId);
      }

      const token = issueClientToken({
        cpf,
        clienteId: String(cliente.id),
        status: 'ATIVO',
        secret: requiredSecretField(jwtConfig, 'secret'),
        issuer: process.env.JWT_ISSUER ?? 'siase-auth',
        expiresIn: process.env.JWT_EXPIRATION ?? '1h'
      });
      log('info', 'Token emitido', { correlationId, subject: cpf, clienteId: String(cliente.id) });
      return response(200, { token, tokenType: 'Bearer', expiresIn: process.env.JWT_EXPIRATION ?? '1h' }, correlationId);
    } catch (error) {
      if (error instanceof InputError) {
        return response(400, 'REQUISICAO_INVALIDA', correlationId);
      }
      log('error', 'Falha ao emitir token', { correlationId, error: error.message });
      return response(500, 'ERRO_INTERNO', correlationId);
    }
  };
}

export const handler = createTokenHandler();

function createPool(config) {
  const value = databaseConfig(config);
  return new Pool({
    host: value.host,
    port: value.port,
    database: value.database,
    user: value.user,
    password: value.password,
    max: 2,
    idleTimeoutMillis: 10000,
    connectionTimeoutMillis: 5000,
    ssl: {
      ca: readFileSync(
        process.env.RDS_CA_BUNDLE_PATH
          ?? fileURLToPath(new URL('../certs/global-bundle.pem', import.meta.url)),
        'utf8'
      ),
      rejectUnauthorized: true
    }
  });
}

function databaseConfig(config) {
  const value = typeof config === 'string' ? JSON.parse(config) : config;
  return {
    ...value,
    host: process.env.DB_HOST ?? value.host,
    port: Number(value.port ?? 5432),
    database: process.env.DB_NAME ?? value.database ?? value.dbname,
    user: value.username ?? value.user,
    password: value.password
  };
}

function requiredSecretField(config, field) {
  const value = typeof config === 'string' ? config : config?.[field];
  if (!value) {
    throw new Error(`Campo ${field} ausente no segredo JWT`);
  }
  return value;
}

function parseBody(event) {
  if (!event?.body) {
    return {};
  }
  const raw = event.isBase64Encoded
    ? Buffer.from(event.body, 'base64').toString('utf8')
    : event.body;
  if (typeof raw !== 'string' || !raw.trim()) {
    throw new InputError('Corpo JSON ausente');
  }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new InputError('Corpo JSON deve ser um objeto');
    }
    return parsed;
  } catch (error) {
    if (error instanceof InputError) {
      throw error;
    }
    throw new InputError('Corpo JSON malformado');
  }
}

class InputError extends Error {}

function response(statusCode, body, correlationId) {
  return {
    statusCode,
    headers: {
      'content-type': 'application/json',
      'X-Correlation-Id': correlationId
    },
    body: JSON.stringify(typeof body === 'string' ? { error: body } : body)
  };
}

export function resetPool() {
  pool = undefined;
}
