import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import { ensurePaymentIntentsTable } from './paymentIntents';
import { clearAllExpiredPremiumInDatabase } from './userDirectory';

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
