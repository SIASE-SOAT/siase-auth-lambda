import test from 'node:test';
import assert from 'node:assert/strict';
import { isValidCpf, normalizeCpf } from '../src/cpf.js';

test('aceita CPF formatado válido', () => {
  assert.equal(isValidCpf('529.982.247-25'), true);
  assert.equal(normalizeCpf('529.982.247-25'), '52998224725');
});

test('rejeita dígito verificador errado', () => {
  assert.equal(isValidCpf('529.982.247-26'), false);
});

test('rejeita CPF com dígitos repetidos', () => {
  assert.equal(isValidCpf('111.111.111-11'), false);
});

test('rejeita tamanho inválido', () => {
  assert.equal(isValidCpf('5299822472'), false);
});
