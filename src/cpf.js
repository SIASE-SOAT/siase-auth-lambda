export function normalizeCpf(value) {
  return typeof value === 'string' ? value.replace(/\D/g, '') : '';
}

export function isValidCpf(value) {
  const cpf = normalizeCpf(value);
  if (cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) {
    return false;
  }

  const first = calculateDigit(cpf.slice(0, 9));
  const second = calculateDigit(cpf.slice(0, 10));
  return cpf === `${cpf.slice(0, 9)}${first}${second}`;
}

function calculateDigit(value) {
  const factor = value.length + 1;
  const sum = [...value].reduce((total, digit, index) => {
    return total + Number(digit) * (factor - index);
  }, 0);
  const remainder = (sum * 10) % 11;
  return remainder === 10 ? 0 : remainder;
}
