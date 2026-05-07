import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import { registerPublicUser, isValidPublicUserId } from './userDirectory';

function planDurationMs(planId: string): number {
  const id = planId.trim().toLowerCase();
  if (id === 'weekly') return 7 * 24 * 60 * 60 * 1000;
  if (id === 'monthly') return 30 * 24 * 60 * 60 * 1000;
  if (id === 'yearly') return 365 * 24 * 60 * 60 * 1000;
  // fallback for custom plan ids
  return 30 * 24 * 60 * 60 * 1000;
}

export async function activatePremiumForUser(args: {
  publicId: string;
  planId: string;
  phone?: string;
  note?: string;
}): Promise<{ premiumUntilMs: number }> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }

  const publicId = String(args.publicId ?? '').trim();
  if (!isValidPublicUserId(publicId)) {
    throw new HttpError(400, 'Invalid user id', 'BAD_PUBLIC_ID');
  }

  const planId = String(args.planId ?? '').trim();
  if (!planId) {
    throw new HttpError(400, 'planId is required', 'BAD_PLAN');
  }

  const phone = (args.phone ?? '').trim();
  const note = (args.note ?? '').trim();

  // Ensure user exists; legacy_user_id will capture phone if present.
  await registerPublicUser({
    publicId,
    profileUsername: publicId,
    phone,
  });

  const now = Date.now();
  const dur = planDurationMs(planId);

  const res = await pool.query<{ premium_until_ms: string | null }>(
    `SELECT premium_until_ms FROM users WHERE id = $1`,
    [publicId],
  );
  const existing = res.rows[0]?.premium_until_ms != null ? Number(res.rows[0]!.premium_until_ms) : null;
  const start = existing != null && Number.isFinite(existing) && existing > now ? existing : now;
  const end = Math.trunc(start + dur);

  await pool.query(
    `UPDATE users
     SET premium_until_ms = $2,
         note = CASE WHEN $3 <> '' THEN $3 ELSE note END,
         updated_at = now()
     WHERE id = $1`,
    [publicId, end, note],
  );

  return { premiumUntilMs: end };
}

