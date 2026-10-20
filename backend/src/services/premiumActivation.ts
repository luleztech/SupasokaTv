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
  const id = planId.trim().toLowerCase().replace(/[\s-]+/g, '_');
  if (id === 'daily' || id === 'day' || id === 'siku' || id === 'siku_1') return MS_DAY;
  if (id === 'weekly' || id === 'week' || id === 'wiki' || id === 'wiki_1' || id === 'wiki_moja') {
    return 7 * MS_DAY;
  }
  if (id === 'monthly' || id === 'month' || id === 'mwezi' || id === 'mwezi_1' || id === 'mwezi_mmoja') {
    return 30 * MS_DAY;
  }
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

/** Duration written in one plan field. Null when this field does not name a period. */
function inferDurationMsFromPlanText(raw: string): number | null {
  const hay = String(raw ?? '').toLowerCase();
  if (!hay.trim()) return null;

  if (/\b(yearly|annual|mwaka|miaka\s*\d+|year)\b/.test(hay)) {
    const n = matchUnitQuantity(hay, 'year|years|mwaka|miaka');
    if (n != null) return n * 365 * MS_DAY;
    return 365 * MS_DAY;
  }

  if (
    /\b(miezi\s*mitatu|miezi\s*3|3\s*miezi|3\s*months|trimest|quarter|robo\s*mwaka)\b/.test(hay) ||
    /\bthree\s*months\b/.test(hay)
  ) {
    return 90 * MS_DAY;
  }
  const mieziN = matchUnitQuantity(hay, 'miezi');
  if (mieziN != null) return mieziN * 30 * MS_DAY;

  if (/\b(mwezi\s*mmoja|mwezi\s*1|1\s*mwezi|monthly|one\s*month|1\s*month)\b/.test(hay)) {
    return 30 * MS_DAY;
  }
  if (/\b(mwezi|month)\b/.test(hay) && !/\bmiezi\b/.test(hay)) {
    return 30 * MS_DAY;
  }

  const wikiN = matchUnitQuantity(hay, 'wiki|weeks?');
  if (wikiN != null) return wikiN * 7 * MS_DAY;
  if (/\b(weekly|wiki\s*moja|wiki|week)\b/.test(hay)) {
    return 7 * MS_DAY;
  }

  const sikuN = matchUnitQuantity(hay, 'siku|days?');
  if (sikuN != null) return sikuN * MS_DAY;

  const hourM = matchUnitQuantity(hay, 'masaa|saa|hours?|hrs?');
  if (hourM != null) return hourM * MS_HOUR;

  return null;
}

/**
 * The plan the user selected. A known id (weekly, monthly, …) wins.
 * Period, then label, describe custom plans. Price lines are not read:
 * they often list other tiers and were turning a week into months.
 */
export function inferDurationMsFromMalipoRow(row: MalipoPlanRow): number {
  const id = row.id.trim().toLowerCase();
  const tzPrimary =
    parseLargestIntFromMoneyText(row.amount) ?? parseLargestIntFromMoneyText(row.price_lines);

  /** Legacy rows: id `yearly` with 12,000 TZS was almost always “miezi 3”, not a full calendar year. */
  if (id === 'yearly' && tzPrimary === 12000) {
    return 90 * MS_DAY;
  }

  const fromSlug = planDurationMsFromSlug(id);
  if (fromSlug != null) return fromSlug;

  const fromPeriod = inferDurationMsFromPlanText(row.period);
  if (fromPeriod != null) return fromPeriod;
  const fromLabel = inferDurationMsFromPlanText(row.label);
  if (fromLabel != null) return fromLabel;

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

/** Public helper for maintenance / reconcile capping. */
export async function resolvePlanDurationMsForPlanId(planId: string): Promise<number> {
  const pool = getPool();
  if (!pool) return planDurationMsFromSlug(planId.trim()) ?? 30 * MS_DAY;
  return resolvePlanDurationMs(pool, planId);
}

/**
 * Duration of one confirmed payment. The selected plan wins.
 * With no plan id, a known price tier is used. Otherwise a week, never a free month.
 */
export async function durationMsForPaidOrder(
  planId: string,
  amountTzs?: number | null,
): Promise<number> {
  const trimmed = String(planId ?? '').trim();
  if (trimmed) return resolvePlanDurationMsForPlanId(trimmed);
  if (amountTzs != null && Number.isFinite(amountTzs)) {
    const fromAmount = durationMsFromKnownTzAmountTiers(Math.trunc(amountTzs));
    if (fromAmount != null) return fromAmount;
  }
  return 7 * MS_DAY;
}

/** Stack each confirmed payment onto the previous end. One row is one period. */
export function stackPaidPremiumEndMs(
  payments: Array<{ activatedAtMs: number; durationMs: number }>,
): number {
  let expected = 0;
  for (const pay of payments) {
    if (!Number.isFinite(pay.activatedAtMs) || pay.activatedAtMs <= 0) continue;
    if (!Number.isFinite(pay.durationMs) || pay.durationMs <= 0) continue;
    const start = Math.max(expected, pay.activatedAtMs);
    expected = start + pay.durationMs;
  }
  return expected;
}

/**
 * Premium end = base + plan duration.
 * When renewing while still premium, base is the current end so leftover time is kept.
 */
export function computePremiumEndMs(activatedAtMs: number, durationMs: number): number {
  return Math.trunc(activatedAtMs + durationMs);
}

function mergePremiumNote(existingNote: string, note: string): string {
  const clearedRevoke = existingNote
    .replace(/(\s*\|\s*)?premium_revoked:(admin|no_verified_payment)/gi, '')
    .replace(/^\s*\|\s*|\s*\|\s*$/g, '')
    .trim();
  if (!note) return clearedRevoke;
  if (clearedRevoke.includes(note)) return clearedRevoke;
  return clearedRevoke ? `${clearedRevoke} | ${note}` : note;
}

export async function activatePremiumForUser(args: {
  publicId: string;
  planId: string;
  phone?: string;
  note?: string;
  /** When set, this paid order can add its period only once. */
  orderId?: string;
  amountTzs?: number | null;
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
  const dur = await durationMsForPaidOrder(planId, args.amountTzs);
  const orderId = String(args.orderId ?? '').trim();

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (orderId) {
      const locked = await client.query<{ premium_granted_until_ms: string | null }>(
        `SELECT premium_granted_until_ms
         FROM payment_intents
         WHERE order_id = $1
         FOR UPDATE`,
        [orderId],
      );
      const grantedRaw = locked.rows[0]?.premium_granted_until_ms;
      const granted = grantedRaw != null ? Number(grantedRaw) : NaN;
      if (Number.isFinite(granted) && granted > 0) {
        const current = await client.query<{ premium_until_ms: string | null }>(
          `SELECT premium_until_ms FROM users WHERE id = $1`,
          [publicId],
        );
        await client.query('COMMIT');
        const until = Number(current.rows[0]?.premium_until_ms ?? granted);
        return { premiumUntilMs: Number.isFinite(until) && until > 0 ? until : granted };
      }
    }

    const user = await client.query<{ premium_until_ms: string | null; note: string | null }>(
      `SELECT premium_until_ms, note FROM users WHERE id = $1 FOR UPDATE`,
      [publicId],
    );
    const existingMs = Number(user.rows[0]?.premium_until_ms ?? 0);
    const baseMs = Number.isFinite(existingMs) && existingMs > now ? existingMs : now;
    const end = computePremiumEndMs(baseMs, dur);
    const nextNote = mergePremiumNote(String(user.rows[0]?.note ?? ''), note);

    const res = await client.query(
      `UPDATE users
       SET premium_until_ms = $2,
           note = $3,
           updated_at = now()
       WHERE id = $1`,
      [publicId, end, nextNote],
    );
    if ((res.rowCount ?? 0) === 0) {
      throw new HttpError(500, 'Failed to set premium on user record', 'PREMIUM_UPDATE_FAILED');
    }

    if (orderId) {
      await client.query(
        `UPDATE payment_intents
         SET status = 'COMPLETED',
             activated_at_ms = COALESCE(activated_at_ms, $2),
             premium_granted_until_ms = COALESCE(premium_granted_until_ms, $3),
             updated_at = now()
         WHERE order_id = $1`,
        [orderId, now, end],
      );
    }

    await client.query('COMMIT');
    return { premiumUntilMs: end };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
