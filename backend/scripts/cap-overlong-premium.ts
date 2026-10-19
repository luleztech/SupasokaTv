/**
 * Cap overlong premium windows to verified payment durations and backfill
 * one-shot grant markers so subscriptions cannot renew forever after expiry.
 *
 * Usage (from backend/):
 *   DATABASE_URL='…' npx tsx scripts/cap-overlong-premium.ts
 *   DATABASE_URL='…' npx tsx scripts/cap-overlong-premium.ts --dry-run
 */
import 'dotenv/config';
import { capOverlongPremiumFromPayments } from '../src/services/premiumCleanup';

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const out = await capOverlongPremiumFromPayments({ dryRun, limit: 5000 });
  console.log(JSON.stringify({ ok: true, dryRun, ...out }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
