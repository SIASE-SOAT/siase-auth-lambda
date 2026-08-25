import { correlationIdFromEvent, log } from './log.js';
import { getSecret } from './secrets.js';
import { verifyClientToken } from './token-service.js';

export async function handler(event) {
  const correlationId = correlationIdFromEvent(event);
  try {
    const token = event?.identitySource?.[0]?.replace(/^Bearer\s+/i, '');
    if (!token) {
      return deny('Token ausente', correlationId);
    }
    const config = await getSecret(process.env.JWT_SECRET_ARN);
    const claims = verifyClientToken(token, secretValue(config), process.env.JWT_ISSUER ?? 'siase-auth');
    if (!claims.clienteId) {
      return deny('Token externo ausente', correlationId);
    }

    return {
      isAuthorized: true,
      context: {
        sub: claims.sub,
        clienteId: String(claims.clienteId),
        roles: Array.isArray(claims.roles) ? claims.roles.join(',') : String(claims.roles ?? '')
      }
    };
  } catch (error) {
    log('warn', 'Token rejeitado pelo authorizer', { correlationId, error: error.message });
    return deny('Token inválido', correlationId);
  }
}

function secretValue(config) {
  return typeof config === 'string' ? config : config?.secret;
}

function deny(reason, correlationId) {
  log('info', 'Requisição não autorizada', { correlationId, reason });
  return { isAuthorized: false };
}
