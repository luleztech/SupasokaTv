import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import {
  ensurePaymentIntentsTable,
  markIntentPremiumGranted,
} from './paymentIntents';
import { resolvePlanDurationMsForPlanId } from './premiumActivation';
import { clearAllExpiredPremiumInDatabase } from './userDirectory';
import { logger } from '../lib/logger';

export type RevokeMistakenPremiumResult = {
  expiredCleared: number;
  activeRevoked: number;
  revokedRepaired: number;
  revokedUserIds: string[];
};

/**
 * Removes premium from users who have no verified completed payment on record.
 * Keeps premium only for users with at least one payment_intents.activated_at_ms.
 */
export async function revokePremiumWithoutVerifiedPayment(): Promise<RevokeMistakenPremiumResult> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }

  await ensurePaymentIntentsTable();
  const now = Date.now();
  const expiredCleared = await clearAllExpiredPremiumInDatabase();

  const preview = await pool.query<{ id: string }>(
    `SELECT u.id
     FROM users u
     WHERE u.premium_until_ms IS NOT NULL
       AND u.premium_until_ms > $1
       AND NOT EXISTS (
         SELECT 1
         FROM payment_intents pi
         WHERE pi.public_id = u.id
           AND pi.activated_at_ms IS NOT NULL
       )
     ORDER BY u.id`,
    [now],
  );

  const revokedUserIds = preview.rows.map((r) => r.id);

  let activeRevoked = 0;
  if (revokedUserIds.length > 0) {
    const res = await pool.query(
      `UPDATE users u
       SET premium_until_ms = $1,
           note = CASE
             WHEN COALESCE(u.note, '') = '' THEN 'premium_revoked:no_verified_payment'
             WHEN u.note LIKE '%premium_revoked:no_verified_payment%' THEN u.note
             ELSE u.note || ' | premium_revoked:no_verified_payment'
           END,
           updated_at = now()
       WHERE u.premium_until_ms IS NOT NULL
         AND u.premium_until_ms > $1
         AND NOT EXISTS (
           SELECT 1
           FROM payment_intents pi
           WHERE pi.public_id = u.id
             AND pi.activated_at_ms IS NOT NULL
         )`,
      [now],
    );
    activeRevoked = res.rowCount ?? 0;
  }

  const repairRes = await pool.query(
    `UPDATE users u
     SET premium_until_ms = $1,
         updated_at = now()
     WHERE u.premium_until_ms IS NULL
       AND u.note LIKE '%premium_revoked:no_verified_payment%'
       AND NOT EXISTS (
         SELECT 1
         FROM payment_intents pi
         WHERE pi.public_id = u.id
           AND pi.activated_at_ms IS NOT NULL
       )`,
    [now],
  );

  return {
    expiredCleared,
    activeRevoked,
    revokedRepaired: repairRes.rowCount ?? 0,
    revokedUserIds,
  };
}

export type RevokeAllPremiumResult = {
  revoked: number;
  revokedUserIds: string[];
};

/**
 * Unconditionally removes premium from every currently-active user, including
 * ones with a verified completed payment. Unlike
 * `revokePremiumWithoutVerifiedPayment`, this does not check payment history —
 * it's a deliberate, irreversible bulk action and must only be reachable from
 * an explicit admin confirmation.
 */
export async function revokeAllActivePremium(): Promise<RevokeAllPremiumResult> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }

  const now = Date.now();
  const preview = await pool.query<{ id: string }>(
    `SELECT id FROM users WHERE premium_until_ms IS NOT NULL AND premium_until_ms > $1 ORDER BY id`,
    [now],
  );
  const revokedUserIds = preview.rows.map((r) => r.id);

  let revoked = 0;
  if (revokedUserIds.length > 0) {
    const res = await pool.query(
      `UPDATE users
       SET premium_until_ms = $1,
           note = CASE
             WHEN COALESCE(note, '') = '' THEN 'premium_revoked:admin'
             WHEN note LIKE '%premium_revoked:%' THEN note
             ELSE note || ' | premium_revoked:admin'
           END,
           updated_at = now()
       WHERE premium_until_ms IS NOT NULL
         AND premium_until_ms > $1`,
      [now],
    );
    revoked = res.rowCount ?? 0;
  }

  return { revoked, revokedUserIds };
}

export type CapOverlongPremiumResult = {
  scanned: number;
  capped: number;
  expiredNow: number;
  grantsBackfilled: number;
  samples: Array<{
    userId: string;
    wasUntilMs: number;
    expectedUntilMs: number;
    daysOver: number;
  }>;
};

/**
 * Cap active premium to the stacked window earned from verified payments,
 * and backfill premium_granted_until_ms so reconcile cannot re-extend forever.
 */
export async function capOverlongPremiumFromPayments(
  opts?: { dryRun?: boolean; limit?: number },
): Promise<CapOverlongPremiumResult> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  await ensurePaymentIntentsTable();

  const dryRun = opts?.dryRun === true;
  const limit = Math.max(1, Math.min(5000, opts?.limit ?? 2000));
  const now = Date.now();

  const users = await pool.query<{ id: string; premium_until_ms: string }>(
    `SELECT id, premium_until_ms
     FROM users
     WHERE premium_until_ms IS NOT NULL
       AND premium_until_ms > $1
     ORDER BY premium_until_ms DESC
     LIMIT $2`,
    [now, limit],
  );

  let capped = 0;
  let expiredNow = 0;
  let grantsBackfilled = 0;
  const samples: CapOverlongPremiumResult['samples'] = [];

  for (const u of users.rows) {
    const userId = u.id;
    const wasUntil = Number(u.premium_until_ms);
    const pays = await pool.query<{
      order_id: string;
      plan_id: string | null;
      activated_at_ms: string;
      premium_granted_until_ms: string | null;
    }>(
      `SELECT order_id, plan_id, activated_at_ms, premium_granted_until_ms
       FROM payment_intents
       WHERE public_id = $1
         AND activated_at_ms IS NOT NULL
       ORDER BY activated_at_ms ASC`,
      [userId],
    );

    if (pays.rows.length === 0) {
      continue;
    }

    let expected = 0;
    for (const pay of pays.rows) {
      const activatedAt = Number(pay.activated_at_ms);
      if (!Number.isFinite(activatedAt) || activatedAt <= 0) continue;
      const planId = String(pay.plan_id ?? '').trim() || 'monthly';
      const dur = await resolvePlanDurationMsForPlanId(planId);
      const start = Math.max(expected, activatedAt);
      expected = start + dur;

      if (pay.premium_granted_until_ms == null) {
        grantsBackfilled += 1;
        if (!dryRun) {
          await markIntentPremiumGranted(pay.order_id, start + dur);
        }
      }
    }

    if (!Number.isFinite(expected) || expected <= 0) continue;

    // Small clock/grace skew (2 hours) before treating as overlong.
    if (wasUntil <= expected + 2 * 60 * 60 * 1000) continue;

    const daysOver = Math.round((wasUntil - expected) / (24 * 60 * 60 * 1000));
    if (samples.length < 40) {
      samples.push({
        userId,
        wasUntilMs: wasUntil,
        expectedUntilMs: expected,
        daysOver,
      });
    }

    if (!dryRun) {
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
         WHERE id = $1`,
        [userId, nextUntil],
      );
      if (nextUntil <= now) expiredNow += 1;
    }
    capped += 1;
    logger.info(
      { userId, wasUntil, expected, daysOver, dryRun },
      'premium_capped_to_payments',
    );
  }

  return {
    scanned: users.rows.length,
    capped,
    expiredNow,
    grantsBackfilled,
    samples,
  };
}
