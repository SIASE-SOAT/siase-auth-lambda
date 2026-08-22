import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { handler } from '../src/authorizer.js';
import { clearSecretCache } from '../src/secrets.js';

test('authorizer aceita token externo válido', async () => {
  clearSecretCache();
  process.env.JWT_SECRET_ARN = 'jwt';
  process.env.JWT_ISSUER = 'siase-auth';
  const originalSend = (await import('@aws-sdk/client-secrets-manager')).SecretsManagerClient.prototype.send;
  (await import('@aws-sdk/client-secrets-manager')).SecretsManagerClient.prototype.send = async () => ({
    SecretString: JSON.stringify({ secret: 'c2lhc2UtaW50ZXJvcGVyYWJpbGl0eS1zZWNyZXQtMzJieXRlcyEh' })
  });
  const token = jwt.sign({ clienteId: 'client-1', roles: ['ROLE_CLIENTE'] },
    Buffer.from('siase-interoperability-secret-32bytes!!'), {
    subject: '52998224725', issuer: 'siase-auth', expiresIn: '1h', algorithm: 'HS256'
  });
  const result = await handler({ identitySource: [`Bearer ${token}`] });
  assert.equal(result.isAuthorized, true);
  assert.deepEqual(result.context, {
    sub: '52998224725', clienteId: 'client-1', roles: 'ROLE_CLIENTE'
  });
  (await import('@aws-sdk/client-secrets-manager')).SecretsManagerClient.prototype.send = originalSend;
});
