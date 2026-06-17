import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import { ensurePaymentIntentsTable } from './paymentIntents';
import { clearAllExpiredPremiumInDatabase } from './userDirectory';

export type RevokeMistakenPremiumResult = {
  expiredCleared: number;
  activeRevoked: number;
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

  if (revokedUserIds.length === 0) {
    return { expiredCleared, activeRevoked: 0, revokedUserIds: [] };
  }

  const res = await pool.query(
    `UPDATE users u
     SET premium_until_ms = NULL,
         note = CASE
           WHEN COALESCE(u.note, '') = '' THEN 'premium_revoked:no_verified_payment'
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

  return {
    expiredCleared,
    activeRevoked: res.rowCount ?? 0,
    revokedUserIds,
  };
}
