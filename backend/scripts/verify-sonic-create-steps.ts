/**
 * Sanity: checkout must try primary → alt format → channel (non-Vodacom) without spamming.
 * Run: npx tsx scripts/verify-sonic-create-steps.ts
 */
import { buildSonicCreateStepsForTest } from '../src/services/sonicPesa';
import {
  clearPaymentStartCooldown,
  markPaymentStartSent,
  paymentStartCooldownMessage,
} from '../src/services/paymentStartCooldown';

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function main() {
  const tigo = buildSonicCreateStepsForTest('0712345678');
  assert(tigo.length === 2, `Tigo expected 2 Sonic steps, got ${tigo.length}`);
  assert(tigo[0]!.buyer_phone.startsWith('0'), 'Tigo primary should be local 0…');
  assert(tigo[1]!.buyer_phone.startsWith('255'), 'Tigo alt should be intl 255…');
  assert(Boolean(tigo[1]!.channel), 'Tigo alt step should include channel hint');

  const halotel = buildSonicCreateStepsForTest('0622345678');
  assert(halotel.length === 2, `Halotel expected 2 Sonic steps, got ${halotel.length}`);
  assert(Boolean(halotel[1]!.channel), 'Halotel alt step should include channel hint');

  const mpesa = buildSonicCreateStepsForTest('0752345678');
  assert(mpesa.length === 2, `M-Pesa expected 2 Sonic steps, got ${mpesa.length}`);
  assert(mpesa[0]!.buyer_phone.startsWith('255'), 'M-Pesa primary should be intl 255…');

  assert(paymentStartCooldownMessage('0712345678') === null, 'no cooldown before success');
  markPaymentStartSent('0712345678', 'order-test-1');
  assert(
    paymentStartCooldownMessage('0712345678') != null,
    'cooldown after successful STK dispatch',
  );
  clearPaymentStartCooldown('0712345678');
  assert(paymentStartCooldownMessage('0712345678') === null, 'cooldown clears on reset');

  console.log(
    JSON.stringify({ ok: true, tigo: tigo.length, halotel: halotel.length, mpesa: mpesa.length }),
  );
}

main();
