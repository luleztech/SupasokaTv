import { getPool } from '../db/pool';
import { logger } from '../lib/logger';
import { ensurePaymentIntentsTable } from './paymentIntents';
import { adminGrantMs } from './premiumGrantNote';
import { paidPremiumCeilingMs, type PaidOrderForCeiling } from './premiumCeiling';

export { adminGrantMs, noteWithAdminGrant, noteWithoutAdminGrant } from './premiumGrantNote';
export { paidPremiumCeilingMs } from './premiumCeiling';

/**
 * Slack before an end time is treated as "longer than paid". Generous on purpose:
 * trimming a customer early costs far more than leaving a few hours too long.
 */
const GRACE_MS = 6 * 60 * 60 * 1000;

type PaidOrderRow = {
  order_id: string;
  plan_id: string | null;
  amount_tzs: string | null;
  activated_at_ms: string;
  premium_granted_until_ms: string | null;
};

/**
 * Every confirmed order that belongs to this account: ordered by the account
 * itself, or by a phone number the account is registered under (any stored shape).
 */
export async function loadPaidOrdersForUser(
  userId: string,
  phone: string,
): Promise<PaidOrderForCeiling[]> {
  const pool = getPool();
  if (!pool) return [];
  await ensurePaymentIntentsTable();

  const { phoneIdentityCandidates } = await import('./userDirectory.js');
  const phones = phoneIdentityCandidates(phone);

  const pays = await pool.query<PaidOrderRow>(
    `SELECT DISTINCT ON (order_id)
            order_id, plan_id, amount_tzs, activated_at_ms, premium_granted_until_ms
     FROM payment_intents
     WHERE activated_at_ms IS NOT NULL
       AND (
         public_id = $1
         OR (cardinality($2::text[]) > 0 AND (
           buyer_phone = ANY($2::text[])
           OR public_id IN (SELECT id FROM users WHERE legacy_user_id = ANY($2::text[]))
         ))
       )
     ORDER BY order_id, activated_at_ms ASC`,
    [userId, phones],
  );
  if (pays.rows.length === 0) return [];

  const { durationMsForPaidOrder } = await import('./premiumActivation.js');
  const out: PaidOrderForCeiling[] = [];
  for (const pay of pays.rows) {
    const activatedAtMs = Number(pay.activated_at_ms);
    const grantedRaw = pay.premium_granted_until_ms != null ? Number(pay.premium_granted_until_ms) : NaN;
    const grantedUntilMs = Number.isFinite(grantedRaw) && grantedRaw > 0 ? grantedRaw : null;
    const order: PaidOrderForCeiling = { activatedAtMs, grantedUntilMs, fallbackDurationMs: 0 };
    // The plan table is only consulted for legacy orders that never recorded a window.
    const needsFallback =
      grantedUntilMs == null || !(grantedUntilMs > activatedAtMs);
    if (needsFallback) {
      const amount = pay.amount_tzs != null ? Number(pay.amount_tzs) : null;
      order.fallbackDurationMs = await durationMsForPaidOrder(String(pay.plan_id ?? ''), amount);
    }
    out.push(order);
  }
  return out;
}

/**
 * Trim an active subscription that runs past everything the account's confirmed
 * payments granted (and past any admin grant). It never trims a window that a
 * recorded payment actually wrote, so editing or re-importing the plan list can
 * no longer cut a paying customer short.
 */
export async function enforcePaidPremiumWindow(userId: string): Promise<void> {
  const pool = getPool();
  const trimmed = String(userId ?? '').trim();
  if (!pool || !trimmed) return;

  const user = await pool.query<{
    premium_until_ms: string | null;
    legacy_user_id: string | null;
    note: string | null;
  }>(
    `SELECT premium_until_ms, legacy_user_id, note FROM users WHERE id = $1`,
    [trimmed],
  );
  const row = user.rows[0];
  if (!row) return;
  const wasUntil = row.premium_until_ms != null ? Number(row.premium_until_ms) : 0;
  if (!Number.isFinite(wasUntil)) return;
  const now = Date.now();
  // Nothing to trim when the window is already over, and admin grants are never trimmed.
  if (wasUntil <= now) return;
  if (adminGrantMs(row.note) > now) return;

  const phone = String(row.legacy_user_id ?? '').trim();
  const orders = await loadPaidOrdersForUser(trimmed, phone.length >= 9 ? phone : '');
  if (orders.length === 0) return;

  const expected = paidPremiumCeilingMs(orders);
  if (!Number.isFinite(expected) || expected <= 0) return;
  if (wasUntil <= expected + GRACE_MS) return;

  const nextUntil = expected <= now ? now : Math.trunc(expected);
  await pool.query(
    `UPDATE users
     SET premium_until_ms = $2,
         note = CASE
           WHEN COALESCE(note, '') LIKE '%premium_capped:payments%' THEN note
           WHEN COALESCE(note, '') = '' THEN 'premium_capped:payments'
           ELSE note || ' | premium_capped:payments'
         END,
         updated_at = now()
     WHERE id = $1
       AND premium_until_ms IS NOT NULL
       AND premium_until_ms > $3`,
    [trimmed, nextUntil, expected + GRACE_MS],
  );
  logger.info(
    {
      userId: trimmed,
      wasUntil,
      expected,
      daysOver: Math.round((wasUntil - expected) / (24 * 60 * 60 * 1000)),
    },
    'premium_capped_to_paid_selection',
  );
}
