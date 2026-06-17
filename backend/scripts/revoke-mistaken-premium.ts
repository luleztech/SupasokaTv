/**
 * One-off maintenance: revoke premium for users without a verified payment.
 *
 * Usage (from backend/):
 *   DATABASE_URL='postgresql://...' npx ts-node --project tsconfig.json scripts/revoke-mistaken-premium.ts
 */
import 'dotenv/config';
import { revokePremiumWithoutVerifiedPayment } from '../src/services/premiumCleanup';

async function main() {
  const out = await revokePremiumWithoutVerifiedPayment();
  console.log(JSON.stringify({ ok: true, ...out }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
