/**
 * Sanity: SonicPesa-only checkout must try multiple steps per wallet.
 * Run: npx tsx scripts/verify-sonic-create-steps.ts
 */
import { buildSonicCreateStepsForTest } from '../src/services/sonicPesa';

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function main() {
  const tigo = buildSonicCreateStepsForTest('0712345678');
  assert(tigo.length >= 5, `Tigo expected >=5 Sonic steps, got ${tigo.length}`);

  const halotel = buildSonicCreateStepsForTest('0622345678');
  assert(halotel.length >= 5, `Halotel expected >=5 Sonic steps, got ${halotel.length}`);

  const mpesa = buildSonicCreateStepsForTest('0752345678');
  assert(mpesa.length >= 3, `M-Pesa expected >=3 Sonic steps, got ${mpesa.length}`);

  console.log(
    JSON.stringify({ ok: true, tigo: tigo.length, halotel: halotel.length, mpesa: mpesa.length }),
  );
}

main();
