/**
 * Sanity: non-Vodacom wallets must get multiple Sonic steps when Aurax is off.
 * Run: npx tsx scripts/verify-sonic-create-steps.ts
 */
import { buildSonicCreateStepsForTest } from '../src/services/sonicPesa';

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function main() {
  const tigoFull = buildSonicCreateStepsForTest('0712345678', { limitNonVodacomAttempts: false });
  assert(tigoFull.length >= 3, `Tigo full path expected >=3 steps, got ${tigoFull.length}`);

  const tigoLight = buildSonicCreateStepsForTest('0712345678', { limitNonVodacomAttempts: true });
  assert(tigoLight.length === 1, `Tigo Aurax-backup expected 1 step, got ${tigoLight.length}`);

  const mpesa = buildSonicCreateStepsForTest('0752345678', { limitNonVodacomAttempts: false });
  assert(mpesa.length >= 2, `M-Pesa expected >=2 steps, got ${mpesa.length}`);

  console.log(JSON.stringify({ ok: true, tigoFull: tigoFull.length, tigoLight: tigoLight.length, mpesa: mpesa.length }));
}

main();
