/**
 * Pure helpers that decide how far a paid subscription may legitimately run.
 *
 * The ceiling is built from what was ACTUALLY granted when each order was
 * activated (`premium_granted_until_ms`). Only legacy orders that never recorded
 * a grant fall back to re-deriving a duration from the plan. Re-deriving every
 * time from the *current* plan table was shortening live subscriptions whenever
 * an admin edited, renamed, re-imported or deleted a plan after the customer paid.
 */

export type PaidOrderForCeiling = {
  /** When the order was activated (epoch ms). */
  activatedAtMs: number;
  /** End of the window written when this order was activated, if it was recorded. */
  grantedUntilMs: number | null;
  /** Fallback length for legacy orders without a recorded grant. */
  fallbackDurationMs: number;
};

function finitePositive(n: number | null | undefined): n is number {
  return n != null && Number.isFinite(n) && n > 0;
}

/** True when the order recorded a real window end (not a legacy stamp in the past). */
export function hasRecordedGrant(order: PaidOrderForCeiling): boolean {
  return (
    finitePositive(order.grantedUntilMs) &&
    finitePositive(order.activatedAtMs) &&
    order.grantedUntilMs > order.activatedAtMs
  );
}

/**
 * End of the window that confirmed payments earned. Orders are applied oldest
 * first. A recorded grant is trusted as-is; a legacy order stacks its plan
 * length on whatever came before it.
 */
export function paidPremiumCeilingMs(orders: PaidOrderForCeiling[]): number {
  const sorted = [...orders]
    .filter((o) => finitePositive(o.activatedAtMs))
    .sort((a, b) => a.activatedAtMs - b.activatedAtMs);
  let end = 0;
  for (const order of sorted) {
    if (hasRecordedGrant(order)) {
      end = Math.max(end, order.grantedUntilMs as number);
      continue;
    }
    if (!finitePositive(order.fallbackDurationMs)) continue;
    end = Math.max(end, order.activatedAtMs) + order.fallbackDurationMs;
  }
  return end;
}
