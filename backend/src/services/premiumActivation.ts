import type { Pool } from 'pg';
import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import { registerPublicUser, isValidPublicUserId } from './userDirectory';

const MS_HOUR = 60 * 60 * 1000;
const MS_DAY = 24 * MS_HOUR;

export { MS_HOUR, MS_DAY };

type MalipoPlanRow = {
  id: string;
  period: string;
  label: string;
  amount: string;
  price_lines: string;
};

export function planDurationMsFromSlug(planId: string): number | null {
  const id = planId.trim().toLowerCase();
  if (id === 'daily') return MS_DAY;
  if (id === 'weekly') return 7 * MS_DAY;
  if (id === 'monthly') return 30 * MS_DAY;
  /** Three calendar months (90d) — common malipo tier, not a full year. */
  if (
    id === 'quarterly' ||
    id === 'quarter' ||
    id === 'three_month' ||
    id === 'trimestrial' ||
    id === 'miezi_3' ||
    id === 'miezi3'
  ) {
    return 90 * MS_DAY;
  }
  if (id === 'yearly' || id === 'annual') return 365 * MS_DAY;
  return null;
}

/** Largest contiguous digit run (TZS display strings). */
function parseLargestIntFromMoneyText(s: string): number | null {
  const m = String(s ?? '').match(/\d[\d,]*/g);
  if (!m || m.length === 0) return null;
  let best = 0;
  for (const chunk of m) {
    const n = parseInt(chunk.replace(/\D/g, ''), 10);
    if (Number.isFinite(n) && n > best) best = n;
  }
  return best > 0 ? best : null;
}

/**
 * Default tiers when admin uses classic TZS prices but minimal period text.
 * Override anytime by writing explicit duration in `period` / `label` (e.g. "Miezi 3").
 */
function durationMsFromKnownTzAmountTiers(tzs: number): number | null {
  if (tzs === 2000) return 7 * MS_DAY;
  if (tzs === 5000) return 30 * MS_DAY;
  if (tzs === 12000) return 90 * MS_DAY;
  return null;
}

/**
 * Infer premium window from admin-configured malipo copy (id + period + label + amounts).
 * Most specific patterns first.
 */
export function inferDurationMsFromMalipoRow(row: MalipoPlanRow): number {
  const id = row.id.trim().toLowerCase();
  const tzPrimary =
    parseLargestIntFromMoneyText(row.amount) ?? parseLargestIntFromMoneyText(row.price_lines);

  /** Legacy rows: id `yearly` with 12,000 TZS was almost always “miezi 3”, not a full calendar year. */
  if (id === 'yearly' && tzPrimary === 12000) {
    return 90 * MS_DAY;
  }

  const hay = `${row.id} ${row.period} ${row.label} ${row.amount} ${row.price_lines}`.toLowerCase();

  // --- Years ---
  if (/\b(yearly|annual|mwaka|miaka\s*\d+|year)\b/.test(hay)) {
    const y = hay.match(/\b(\d{1,2})\s*(year|years|mwaka|miaka)\b/);
    if (y) {
      const n = parseInt(y[1]!, 10);
      if (Number.isFinite(n) && n > 0) return n * 365 * MS_DAY;
    }
    return 365 * MS_DAY;
  }

  // --- Three months (explicit before generic "month") ---
  if (
    /\b(miezi\s*mitatu|miezi\s*3|3\s*miezi|3\s*months|trimest|quarter|robo\s*mwaka)\b/.test(hay) ||
    /\bthree\s*months\b/.test(hay)
  ) {
    return 90 * MS_DAY;
  }
  const mieziN = hay.match(/\b(\d{1,2})\s*miezi\b/);
  if (mieziN) {
    const n = parseInt(mieziN[1]!, 10);
    if (Number.isFinite(n) && n > 0) return n * 30 * MS_DAY;
  }

  // --- Single month ---
  if (/\b(mwezi\s*mmoja|mwezi\s*1|1\s*mwezi|monthly|one\s*month|1\s*month)\b/.test(hay)) {
    return 30 * MS_DAY;
  }
  if (/\b(mwezi|month)\b/.test(hay) && !/\bmiezi\b/.test(hay)) {
    return 30 * MS_DAY;
  }

  // --- Weeks ---
  const wikiN = hay.match(/\b(\d{1,2})\s*(wiki|weeks?)\b/);
  if (wikiN) {
    const n = parseInt(wikiN[1]!, 10);
    if (Number.isFinite(n) && n > 0) return n * 7 * MS_DAY;
  }
  if (/\b(weekly|wiki\s*moja|wiki|week)\b/.test(hay)) {
    return 7 * MS_DAY;
  }

  // --- Days ---
  const sikuN = hay.match(/\b(\d{1,3})\s*(siku|days?)\b/);
  if (sikuN) {
    const n = parseInt(sikuN[1]!, 10);
    if (Number.isFinite(n) && n > 0) return n * MS_DAY;
  }

  // --- Hours (masaa / saa) ---
  const hourM = hay.match(/\b(\d{1,3})\s*(masaa|saa|hours?|hrs?)\b/);
  if (hourM) {
    const n = parseInt(hourM[1]!, 10);
    if (Number.isFinite(n) && n > 0) return n * MS_HOUR;
  }

  // --- Fallback: infer from displayed TZS (admin prices) ---
  const tier = tzPrimary != null ? durationMsFromKnownTzAmountTiers(tzPrimary) : null;
  if (tier != null) return tier;

  return 30 * MS_DAY;
}

async function resolvePlanDurationMs(pool: Pool, planId: string): Promise<number> {
  const trimmed = planId.trim();

  const res = await pool.query<MalipoPlanRow>(
    `SELECT id, period, label, amount, price_lines FROM malipo_plans WHERE id = $1`,
    [trimmed],
  );
  const r = res.rows[0];
  if (r) {
    return inferDurationMsFromMalipoRow(r);
  }

  return planDurationMsFromSlug(trimmed) ?? 30 * MS_DAY;
}

/** Each payment grants exactly one plan window from activation time (no stacking). */
export function computePremiumEndMs(activatedAtMs: number, durationMs: number): number {
  return Math.trunc(activatedAtMs + durationMs);
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

  const end = computePremiumEndMs(now, dur);

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
