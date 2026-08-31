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
  if (tzs === 3000) return 7 * MS_DAY;
  if (tzs === 5000) return 30 * MS_DAY;
  if (tzs === 6000) return 30 * MS_DAY;
  if (tzs === 10000) return 90 * MS_DAY;
  if (tzs === 12000) return 90 * MS_DAY;
  return null;
}

/**
 * Digit+unit quantity, accepting either order ("2 wiki" or "wiki 2"). The two
 * fields are matched independently so a bare unit word without a number (e.g.
 * "wiki" alone, meaning "one week") returns null here and is handled by the
 * caller's singular fallback instead of being coerced to some digit.
 */
function matchUnitQuantity(hay: string, unitPattern: string): number | null {
  const digitFirst = hay.match(new RegExp(`\\b(\\d{1,3})\\s*(?:${unitPattern})\\b`));
  if (digitFirst) {
    const n = parseInt(digitFirst[1]!, 10);
    if (Number.isFinite(n) && n > 0) return n;
  }
  const unitFirst = hay.match(new RegExp(`\\b(?:${unitPattern})\\s*(\\d{1,3})\\b`));
  if (unitFirst) {
    const n = parseInt(unitFirst[1]!, 10);
    if (Number.isFinite(n) && n > 0) return n;
  }
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

  /**
   * Fields are joined with a non-whitespace separator on purpose: joining with
   * plain spaces let a trailing digit from one field (e.g. period's "...siku 7")
   * bind to a unit word starting the next field (label's "wiki 1..."), producing
   * a bogus "7 wiki" match worth 49 days for what was actually a 1-week plan.
   * The "|" blocks `\s*` from bridging across field boundaries.
   */
  const hay = `${row.id} | ${row.period} | ${row.label} | ${row.amount} | ${row.price_lines}`.toLowerCase();

  // --- Years ---
  if (/\b(yearly|annual|mwaka|miaka\s*\d+|year)\b/.test(hay)) {
    const n = matchUnitQuantity(hay, 'year|years|mwaka|miaka');
    if (n != null) return n * 365 * MS_DAY;
    return 365 * MS_DAY;
  }

  // --- Three months (explicit before generic "month") ---
  if (
    /\b(miezi\s*mitatu|miezi\s*3|3\s*miezi|3\s*months|trimest|quarter|robo\s*mwaka)\b/.test(hay) ||
    /\bthree\s*months\b/.test(hay)
  ) {
    return 90 * MS_DAY;
  }
  const mieziN = matchUnitQuantity(hay, 'miezi');
  if (mieziN != null) return mieziN * 30 * MS_DAY;

  // --- Single month ---
  if (/\b(mwezi\s*mmoja|mwezi\s*1|1\s*mwezi|monthly|one\s*month|1\s*month)\b/.test(hay)) {
    return 30 * MS_DAY;
  }
  if (/\b(mwezi|month)\b/.test(hay) && !/\bmiezi\b/.test(hay)) {
    return 30 * MS_DAY;
  }

  // --- Weeks ---
  const wikiN = matchUnitQuantity(hay, 'wiki|weeks?');
  if (wikiN != null) return wikiN * 7 * MS_DAY;
  if (/\b(weekly|wiki\s*moja|wiki|week)\b/.test(hay)) {
    return 7 * MS_DAY;
  }

  // --- Days ---
  const sikuN = matchUnitQuantity(hay, 'siku|days?');
  if (sikuN != null) return sikuN * MS_DAY;

  // --- Hours (masaa / saa) ---
  const hourM = matchUnitQuantity(hay, 'masaa|saa|hours?|hrs?');
  if (hourM != null) return hourM * MS_HOUR;

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

/**
 * Premium end = base + plan duration.
 * When renewing while still premium, base is the current end so leftover time is kept.
 */
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

  const phone = (args.phone ?? '').trim();
  const note = (args.note ?? '').trim();

  let publicId = String(args.publicId ?? '').trim();
  if (!isValidPublicUserId(publicId)) {
    throw new HttpError(400, 'Invalid user id', 'BAD_PUBLIC_ID');
  }

  // Never move an active subscription onto a brand-new id when phone already maps to one.
  if (phone) {
    const { findCanonicalUserByPhone, isPremiumUntilActive } = await import('./userDirectory.js');
    const canonical = await findCanonicalUserByPhone(phone);
    if (canonical && isPremiumUntilActive(canonical.premiumUntilMs) && canonical.id) {
      publicId = canonical.id;
    }
  }

  const planId = String(args.planId ?? '').trim();
  if (!planId) {
    throw new HttpError(400, 'planId is required', 'BAD_PLAN');
  }

  // Ensure user exists; legacy_user_id will capture phone if present.
  await registerPublicUser({
    publicId,
    profileUsername: publicId,
    phone,
  });

  const now = Date.now();
  const dur = await resolvePlanDurationMs(pool, planId);

  // Extend from remaining premium when still active (renewals keep leftover time).
  const existing = await pool.query<{ premium_until_ms: string | null }>(
    `SELECT premium_until_ms FROM users WHERE id = $1`,
    [publicId],
  );
  const existingMs = Number(existing.rows[0]?.premium_until_ms ?? 0);
  const baseMs = Number.isFinite(existingMs) && existingMs > now ? existingMs : now;
  const end = computePremiumEndMs(baseMs, dur);

  const res = await pool.query(
    `UPDATE users
     SET premium_until_ms = $2,
         note = CASE
           WHEN $3 <> '' THEN $3
           ELSE trim(both ' |' from regexp_replace(
             COALESCE(note, ''),
             '(\\s*\\|\\s*)?premium_revoked:(admin|no_verified_payment)',
             '',
             'g'
           ))
         END,
         updated_at = now()
     WHERE id = $1`,
    [publicId, end, note],
  );
  if ((res.rowCount ?? 0) === 0) {
    throw new HttpError(500, 'Failed to set premium on user record', 'PREMIUM_UPDATE_FAILED');
  }

  return { premiumUntilMs: end };
}
