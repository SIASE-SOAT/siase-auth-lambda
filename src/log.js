import { randomUUID } from 'node:crypto';

export function correlationIdFromEvent(event) {
  const headers = event?.headers ?? {};
  return headers['X-Correlation-Id']
    ?? headers['x-correlation-id']
    ?? randomUUID();
}

export function log(level, message, fields = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...fields
  }));
}
