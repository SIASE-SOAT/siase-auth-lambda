import test from 'node:test';
import assert from 'node:assert/strict';
import { formatNotification } from '../src/notification.js';

test('formata notificação do cliente', () => {
  assert.equal(
    formatNotification({ clienteId: 'client-1', subject: 'OS finalizada' }),
    'Cliente client-1: OS finalizada'
  );
});

test('falha mensagem sem cliente', () => {
  assert.throws(() => formatNotification({ subject: 'OS finalizada' }), /clienteId/);
});
