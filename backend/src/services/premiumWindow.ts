import { getPool } from '../db/pool';
import { logger } from '../lib/logger';
import { ensurePaymentIntentsTable } from './paymentIntents';

const GRACE_MS = 2 * 60 * 60 * 1000;

/** Latest admin grant in the note. A newer save wins over an older one. */
export function adminGrantMs(note: string | null | undefined): number {
  const text = String(note ?? '');
  let best = 0;
  for (const match of text.matchAll(/premium_admin_grant:(\d{10,})/g)) {
    const n = Number(match[1]);
    if (Number.isFinite(n) && n > best) best = n;
  }
  return best;
}

export function noteWithAdminGrant(note: string | null | undefined, grantMs: number): string {
  const stripped = String(note ?? '')
    .replace(/(\s*\|\s*)?premium_revoked:(admin|no_verified_payment)/gi, '')
    .replace(/(\s*\|\s*)?premium_admin_grant:\d+/gi, '')
    .replace(/\s*\|\s*/g, ' | ')
    .replace(/^\s*\|\s*|\s*\|\s*$/g, '')
    .trim();
  const marker = `premium_admin_grant:${Math.trunc(grantMs)}`;
  return stripped ? `${stripped} | ${marker}` : marker;
}

export function noteWithoutAdminGrant(note: string | null | undefined): string {
  let text = String(note ?? '')
    .replace(/(\s*\|\s*)?premium_admin_grant:\d+/gi, '')
    .replace(/\s*\|\s*/g, ' | ')
    .replace(/^\s*\|\s*|\s*\|\s*$/g, '')
    .trim();
  if (!text.includes('premium_revoked:')) {
    text = text ? `${text} | premium_revoked:admin` : 'premium_revoked:admin';
  }
  return text;
}

/**
 * Shrink an active subscription to the periods that were actually paid.
 * A week selection stays a week. A later paid month stacks on what is left.
 * Accounts with no confirmed payment are left alone (admin grants).
 */
export async function enforcePaidPremiumWindow(userId: string): Promise<void> {
  const pool = getPool();
  const trimmed = String(userId ?? '').trim();
  if (!pool || !trimmed) return;

  await ensurePaymentIntentsTable();
  const { durationMsForPaidOrder, stackPaidPremiumEndMs } = await import('./premiumActivation.js');

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
  const grantMs = adminGrantMs(row.note);
  const adminFloor = grantMs > now ? grantMs : 0;
  if (adminFloor > 0) {
    if (wasUntil < adminFloor) {
      await pool.query(
        `UPDATE users
         SET premium_until_ms = $2, updated_at = now()
         WHERE id = $1 AND (premium_until_ms IS NULL OR premium_until_ms < $2)`,
        [trimmed, adminFloor],
      );
    }
    return;
  }

  const phone = String(row.legacy_user_id ?? '').trim();
  const phoneKey = phone.length >= 9 ? phone : '';
  const pays = await pool.query<{
    order_id: string;
    plan_id: string | null;
    amount_tzs: string | null;
    activated_at_ms: string;
  }>(
    `SELECT DISTINCT ON (order_id) order_id, plan_id, amount_tzs, activated_at_ms
     FROM payment_intents
     WHERE activated_at_ms IS NOT NULL
       AND (
         public_id = $1
         OR ($2 <> '' AND (buyer_phone = $2 OR public_id IN (
           SELECT id FROM users WHERE legacy_user_id = $2
         )))
       )
     ORDER BY order_id, activated_at_ms ASC`,
    [trimmed, phoneKey],
  );
  if (pays.rows.length === 0) return;

  const stacked: Array<{ activatedAtMs: number; durationMs: number }> = [];
  for (const pay of pays.rows) {
    const activatedAt = Number(pay.activated_at_ms);
    const amount = pay.amount_tzs != null ? Number(pay.amount_tzs) : null;
    const durationMs = await durationMsForPaidOrder(String(pay.plan_id ?? ''), amount);
    stacked.push({ activatedAtMs: activatedAt, durationMs });
  }
  stacked.sort((a, b) => a.activatedAtMs - b.activatedAtMs);
  const expected = stackPaidPremiumEndMs(stacked);
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
