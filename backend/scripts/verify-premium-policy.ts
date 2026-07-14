/**
 * Sanity checks for premium duration + expiry policy (no DB required).
 *
 * Usage: npx ts-node --project tsconfig.json scripts/verify-premium-policy.ts
 */
import {
  MS_DAY,
  computePremiumEndMs,
  inferDurationMsFromMalipoRow,
  planDurationMsFromSlug,
} from '../src/services/premiumActivation';
import { isPremiumUntilActive } from '../src/services/userDirectory';

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function assertEq<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${expected}, got ${actual}`);
  }
}

function main() {
  assertEq(planDurationMsFromSlug('daily'), MS_DAY, 'daily');
  assertEq(planDurationMsFromSlug('weekly'), 7 * MS_DAY, 'weekly');
  assertEq(planDurationMsFromSlug('monthly'), 30 * MS_DAY, 'monthly');
  assertEq(planDurationMsFromSlug('quarterly'), 90 * MS_DAY, 'quarterly');
  assertEq(planDurationMsFromSlug('yearly'), 365 * MS_DAY, 'yearly');

  const weeklyRow = inferDurationMsFromMalipoRow({
    id: 'weekly',
    period: 'Wiki 1',
    label: 'Wiki',
    amount: 'TZS 2,000',
    price_lines: '',
  });
  assertEq(weeklyRow, 7 * MS_DAY, 'malipo weekly row');

  const legacyYearly3Mo = inferDurationMsFromMalipoRow({
    id: 'yearly',
    period: '',
    label: '',
    amount: '12000',
    price_lines: '',
  });
  assertEq(legacyYearly3Mo, 90 * MS_DAY, 'legacy yearly 12000 => 3 months');

  const activatedAt = 1_700_000_000_000;
  const end = computePremiumEndMs(activatedAt, 7 * MS_DAY);
  assertEq(end, activatedAt + 7 * MS_DAY, 'exact weekly window');

  // Renewals extend from remaining end (stack leftover time).
  const remainingEnd = activatedAt + 5 * MS_DAY;
  const renewed = computePremiumEndMs(remainingEnd, 7 * MS_DAY);
  assertEq(renewed, remainingEnd + 7 * MS_DAY, 'renewal stacks onto remaining premium');

  const future = Date.now() + MS_DAY;
  const past = Date.now() - MS_DAY;
  assert(isPremiumUntilActive(future), 'future premium is active');
  assert(!isPremiumUntilActive(past), 'past premium is locked');
  assert(!isPremiumUntilActive(null), 'null premium is locked');

  console.log(JSON.stringify({ ok: true, checks: 12 }, null, 2));
}

main();
