import jwt from 'jsonwebtoken';

export function issueClientToken({ cpf, clienteId, status, secret, issuer, expiresIn = '1h' }) {
  return jwt.sign({
    clienteId,
    status,
    roles: ['ROLE_CLIENTE']
  }, decodeBase64Secret(secret), {
    subject: cpf,
    issuer,
    expiresIn,
    algorithm: 'HS256'
  });
}

export function verifyClientToken(token, secret, issuer) {
  return jwt.verify(token, decodeBase64Secret(secret), {
    algorithms: ['HS256'],
    issuer
  });
}

export function decodeBase64Secret(secret) {
  if (typeof secret !== 'string' || !secret.trim()) {
    throw new Error('Segredo JWT ausente');
  }
  const normalized = secret.trim();
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized) || normalized.length % 4 !== 0) {
    throw new Error('Segredo JWT deve ser Base64');
  }
  const decoded = Buffer.from(normalized, 'base64');
  if (decoded.length < 32) {
    throw new Error('Segredo JWT deve ter pelo menos 32 bytes');
  }
  return decoded;
}
