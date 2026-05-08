import type { Pool } from 'pg';
import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import { registerPublicUser, isValidPublicUserId } from './userDirectory';

function planDurationMsFromSlug(planId: string): number | null {
  const id = planId.trim().toLowerCase();
  if (id === 'daily') return 24 * 60 * 60 * 1000;
  if (id === 'weekly') return 7 * 24 * 60 * 60 * 1000;
  if (id === 'monthly') return 30 * 24 * 60 * 60 * 1000;
  if (id === 'yearly') return 365 * 24 * 60 * 60 * 1000;
  return null;
}

/** Infer duration when plan id is a custom key (e.g. UUID) using `malipo_plans.period` text. */
function inferDurationMsFromPlanText(planId: string, period: string): number {
  const hay = `${planId} ${period}`.toLowerCase();
  if (/\b(yearly|annual|mwaka|year)\b/.test(hay)) return 365 * 24 * 60 * 60 * 1000;
  if (/\b(monthly|mwezi|month)\b/.test(hay)) return 30 * 24 * 60 * 60 * 1000;
  if (/\b(weekly|wiki|week)\b/.test(hay)) return 7 * 24 * 60 * 60 * 1000;
  if (/\b(daily|siku\s*1|day\s*pass)\b/.test(hay)) return 24 * 60 * 60 * 1000;
  const m = period.match(/(\d+)\s*(day|days|siku)/i);
  if (m) {
    const n = parseInt(m[1]!, 10);
    if (Number.isFinite(n) && n > 0) return n * 24 * 60 * 60 * 1000;
  }
  return 30 * 24 * 60 * 60 * 1000;
}

async function resolvePlanDurationMs(pool: Pool, planId: string): Promise<number> {
  const trimmed = planId.trim();
  const fromSlug = planDurationMsFromSlug(trimmed);
  if (fromSlug != null) return fromSlug;

  const res = await pool.query<{ period: string }>(`SELECT period FROM malipo_plans WHERE id = $1`, [trimmed]);
  const period = (res.rows[0]?.period ?? '').trim();
  return inferDurationMsFromPlanText(trimmed, period);
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
  const dur = await resolvePlanDurationMs(pool, planId);

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
