import jwt from 'jsonwebtoken';

export function issueClientToken({ cpf, clienteId, status, secret, issuer, expiresIn = '1h' }) {
  return jwt.sign({
    issuer,
    clienteId,
    status,
    roles: ['ROLE_CLIENTE']
  }, secret, {
    subject: cpf,
    issuer,
    expiresIn,
    algorithm: 'HS256'
  });
}

export function verifyClientToken(token, secret, issuer) {
  return jwt.verify(token, secret, {
    algorithms: ['HS256'],
    issuer
  });
}
