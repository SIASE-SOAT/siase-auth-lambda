import { log } from './log.js';
import { randomUUID } from 'node:crypto';

export async function handler(event) {
  for (const record of event?.Records ?? []) {
    const message = parseMessage(record);
    const notification = formatNotification(message);
    log('info', 'Notificação de cliente recebida', {
      correlationId: message.correlationId ?? randomUUID(),
      clienteId: message.clienteId,
      subject: message.subject,
      notification
    });
  }
  return { processed: event?.Records?.length ?? 0 };
}

function parseMessage(record) {
  const raw = record?.Sns?.Message;
  if (!raw) {
    throw new Error('Evento SNS sem mensagem');
  }
  try {
    return typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch {
    return { subject: raw };
  }
}

function formatNotification(message) {
  if (!message.clienteId || !message.subject) {
    throw new Error('Mensagem de notificação sem clienteId ou subject');
  }
  return `Cliente ${message.clienteId}: ${message.subject}`;
}

export { formatNotification };
