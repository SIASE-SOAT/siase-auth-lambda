import { GetSecretValueCommand, SecretsManagerClient } from '@aws-sdk/client-secrets-manager';

const client = new SecretsManagerClient({});
const cache = new Map();

export async function getSecret(secretArn, clientOverride = client) {
  if (cache.has(secretArn)) {
    return cache.get(secretArn);
  }

  const result = await clientOverride.send(new GetSecretValueCommand({
    SecretId: secretArn
  }));
  const value = result.SecretString
    ?? Buffer.from(result.SecretBinary ?? '').toString('utf8');
  if (!value) {
    throw new Error(`Secret ${secretArn} não possui valor`);
  }

  let parsed;
  try {
    parsed = JSON.parse(value);
  } catch {
    parsed = value;
  }
  cache.set(secretArn, parsed);
  return parsed;
}

export function clearSecretCache() {
  cache.clear();
}
