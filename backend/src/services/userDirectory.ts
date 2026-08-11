import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import { normalizePhoneToLocal0, toLocal0Digits } from '../lib/tzPhone';

const publicIdRe = /^User-[A-Za-z2-9]{5}$/;

export function isValidPublicUserId(id: string): boolean {
  return publicIdRe.test(id);
}

export type RegisterPublicUserResult = {
  publicId: string;
  recovered: boolean;
  premiumUntilMs: number | null;
  profileUsername: string;
};

/** Phone shapes we may have stored on `users.legacy_user_id` / `payment_intents.buyer_phone`. */
export function phoneIdentityCandidates(rawPhone: string): string[] {
  const trimmed = String(rawPhone ?? '').trim();
  if (!trimmed) return [];

  const out = new Set<string>();
  out.add(trimmed);

  const digits = trimmed.replace(/\D/g, '');
  if (digits) out.add(digits);

  const norm = normalizePhoneToLocal0(trimmed);
  const local = norm.local ?? (toLocal0Digits(trimmed).length === 10 ? toLocal0Digits(trimmed) : '');
  if (local && /^0\d{9}$/.test(local)) {
    out.add(local);
    const intl = `255${local.slice(1)}`;
    out.add(intl);
    out.add(`+${intl}`);
  }

  return [...out].filter((s) => s.length > 0);
}

type CanonicalPhoneUser = {
  id: string;
  profileUsername: string;
  premiumUntilMs: number | null;
};

/**
 * Prefer the still-subscribed account for this phone so app updates / reinstalls
 * do not orphan an active premium onto a brand-new `User-xxxxx`.
 */
export async function findCanonicalUserByPhone(rawPhone: string): Promise<CanonicalPhoneUser | null> {
  const pool = getPool();
  if (!pool) return null;

  const candidates = phoneIdentityCandidates(rawPhone);
  if (candidates.length === 0) return null;

  const now = Date.now();
  const byLegacy = await pool.query<{
    id: string;
    profile_username: string;
    premium_until_ms: string | null;
  }>(
    `SELECT id, profile_username, premium_until_ms
     FROM users
     WHERE legacy_user_id = ANY($1::text[])
     ORDER BY
       CASE WHEN premium_until_ms IS NOT NULL AND premium_until_ms > $2 THEN 0 ELSE 1 END,
       COALESCE(premium_until_ms, 0) DESC,
       updated_at DESC
     LIMIT 5`,
    [candidates, now],
  );

  for (const row of byLegacy.rows) {
    const premiumUntilMs = row.premium_until_ms != null ? Number(row.premium_until_ms) : null;
    if (isPremiumUntilActive(premiumUntilMs)) {
      return {
        id: row.id,
        profileUsername: row.profile_username,
        premiumUntilMs,
      };
    }
  }

  try {
    const { ensurePaymentIntentsTable } = await import('./paymentIntents.js');
    await ensurePaymentIntentsTable();
    const byIntent = await pool.query<{
      public_id: string;
      profile_username: string | null;
      premium_until_ms: string | null;
    }>(
      `SELECT u.id AS public_id, u.profile_username, u.premium_until_ms
       FROM payment_intents pi
       INNER JOIN users u ON u.id = pi.public_id
       WHERE pi.buyer_phone = ANY($1::text[])
         AND pi.public_id IS NOT NULL
         AND pi.public_id <> ''
         AND u.premium_until_ms IS NOT NULL
         AND u.premium_until_ms > $2
       ORDER BY u.premium_until_ms DESC, pi.updated_at DESC
       LIMIT 1`,
      [candidates, now],
    );
    const hit = byIntent.rows[0];
    if (hit?.public_id) {
      return {
        id: hit.public_id,
        profileUsername: hit.profile_username || hit.public_id,
        premiumUntilMs: hit.premium_until_ms != null ? Number(hit.premium_until_ms) : null,
      };
    }
  } catch {
    /* payment_intents may be unavailable — legacy_user_id path is enough */
  }

  return null;
}

/** First open or returning viewer — upsert in `users` (no admin key). */
export async function registerPublicUser(body: unknown): Promise<RegisterPublicUserResult> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  if (!body || typeof body !== 'object') {
    throw new HttpError(400, 'Invalid JSON body', 'BAD_REQUEST');
  }
  const b = body as Record<string, unknown>;
  let publicId = String(b.publicId ?? '').trim();
  if (!isValidPublicUserId(publicId)) {
    throw new HttpError(400, 'publicId must match User-XXXXX (5 chars A–Z, a–z, 2–9)', 'BAD_PUBLIC_ID');
  }
  let profileUsername = String(b.profileUsername ?? '').trim();
  if (profileUsername.length === 0) profileUsername = publicId;
  if (profileUsername.length > 160) profileUsername = profileUsername.slice(0, 160);

  const rawPhone = String(b.legacyUserId ?? b.userNumber ?? b.phone ?? b.buyerPhone ?? '').trim();
  const phoneNorm = rawPhone ? normalizePhoneToLocal0(rawPhone) : { local: undefined as string | undefined };
  const legacyUserId = phoneNorm.local || rawPhone;

  let recovered = false;
  let premiumUntilMs: number | null = null;

  // Active subscription for this phone always wins — keep the old User id + premium.
  if (legacyUserId) {
    const canonical = await findCanonicalUserByPhone(legacyUserId);
    if (canonical && isPremiumUntilActive(canonical.premiumUntilMs)) {
      if (canonical.id !== publicId) {
        recovered = true;
      }
      publicId = canonical.id;
      profileUsername = canonical.profileUsername || publicId;
      premiumUntilMs = canonical.premiumUntilMs;
    }
  }

  await pool.query(
    `INSERT INTO users (id, profile_username, legacy_user_id, premium_until_ms, note, updated_at)
     VALUES ($1, $2, NULLIF($3, ''), NULL, '', now())
     ON CONFLICT (id) DO UPDATE SET
       profile_username = CASE
         WHEN EXCLUDED.profile_username IS NOT NULL AND TRIM(EXCLUDED.profile_username) <> ''
           THEN EXCLUDED.profile_username
         ELSE users.profile_username
       END,
       legacy_user_id = COALESCE(NULLIF(EXCLUDED.legacy_user_id, ''), users.legacy_user_id),
       updated_at = now()`,
    [publicId, profileUsername, legacyUserId],
  );

  if (premiumUntilMs == null) {
    const row = await getUserPremiumRecord(publicId);
    premiumUntilMs = isPremiumUntilActive(row.premiumUntilMs) ? row.premiumUntilMs : null;
  }

  return {
    publicId,
    recovered,
    premiumUntilMs,
    profileUsername,
  };
}

export type UserRow = {
  id: string;
  profile_username: string;
  legacy_user_id: string | null;
  premium_until_ms: string | null;
  note: string;
  created_at: Date;
  updated_at: Date;
};

export async function listUsersForAdmin(): Promise<
  {
    id: string;
    username: string;
    userNumber: string | null;
    premiumUntilMs: number | null;
    note: string;
    createdAtMs: number;
  }[]
> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  const res = await pool.query<UserRow>(
    `SELECT id, profile_username, legacy_user_id, premium_until_ms, note, created_at, updated_at
     FROM users
     ORDER BY created_at DESC`,
  );
  return res.rows.map((r) => ({
    id: r.id,
    username: r.profile_username,
    userNumber: r.legacy_user_id ?? null,
    premiumUntilMs: r.premium_until_ms != null ? Number(r.premium_until_ms) : null,
    note: r.note ?? '',
    createdAtMs: r.created_at.getTime(),
  }));
}

export async function deleteUserById(id: string): Promise<boolean> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  const trimmed = id.trim();
  if (!trimmed) return false;

  // Void not-yet-activated intents. Do NOT stamp activated_at_ms — that made
  // real paid orders unrecoverable when the same User-xxxxx returned (paid but
  // forever locked). CANCELLED keeps them out of reconcile sweeps.
  const { ensurePaymentIntentsTable } = await import('./paymentIntents.js');
  await ensurePaymentIntentsTable();
  await pool.query(
    `UPDATE payment_intents
     SET status = 'CANCELLED',
         provider_status = 'ADMIN_DELETED',
         updated_at = now()
     WHERE public_id = $1 AND activated_at_ms IS NULL`,
    [trimmed],
  );

  const res = await pool.query(`DELETE FROM users WHERE id = $1`, [trimmed]);
  return (res.rowCount ?? 0) > 0;
}

export function isPremiumUntilActive(premiumUntilMs: number | null | undefined): premiumUntilMs is number {
  return premiumUntilMs != null && Number.isFinite(premiumUntilMs) && premiumUntilMs > Date.now();
}

/** Expired premium stays on the row (past timestamp) so admin can list users as "walioisha". */
export async function clearExpiredPremiumForUser(_userId: string): Promise<void> {
  return;
}

/** Count users whose premium window has ended (playback still locked via isPremiumUntilActive). */
export async function clearAllExpiredPremiumInDatabase(): Promise<number> {
  const pool = getPool();
  if (!pool) return 0;
  const res = await pool.query<{ c: number }>(
    `SELECT COUNT(*)::int AS c
     FROM users
     WHERE premium_until_ms IS NOT NULL
       AND premium_until_ms <= $1`,
    [Date.now()],
  );
  return res.rows[0]?.c ?? 0;
}

export async function getUserPremiumStatus(userId: string): Promise<number | null> {
  const row = await getUserPremiumRecord(userId);
  const raw = row.premiumUntilMs;
  return isPremiumUntilActive(raw) ? raw : null;
}

export function isPremiumRevokeLocked(note: string | null | undefined): boolean {
  return String(note ?? '').includes('premium_revoked:');
}

export async function applyAdminPremiumUpdate(
  userId: string,
  premiumUntilMs: number | null,
): Promise<boolean> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  const trimmed = userId.trim();
  if (!trimmed) return false;

  const now = Date.now();
  const revoke = premiumUntilMs == null || premiumUntilMs <= now;
  const effectiveMs = premiumUntilMs == null ? now : Math.trunc(premiumUntilMs);

  if (revoke) {
    const res = await pool.query(
      `UPDATE users
       SET premium_until_ms = $2,
           note = CASE
             WHEN COALESCE(note, '') = '' THEN 'premium_revoked:admin'
             WHEN note LIKE '%premium_revoked:%' THEN note
             ELSE note || ' | premium_revoked:admin'
           END,
           updated_at = now()
       WHERE id = $1`,
      [trimmed, effectiveMs],
    );
    return (res.rowCount ?? 0) > 0;
  }

  const res = await pool.query(
    `UPDATE users
     SET premium_until_ms = $2,
         note = trim(both ' |' from regexp_replace(
           COALESCE(note, ''),
           '(\\s*\\|\\s*)?premium_revoked:(admin|no_verified_payment)',
           '',
           'g'
         )),
         updated_at = now()
     WHERE id = $1`,
    [trimmed, effectiveMs],
  );
  return (res.rowCount ?? 0) > 0;
}

export async function isUserPremiumRevokeLocked(userId: string): Promise<boolean> {
  const pool = getPool();
  if (!pool) return false;
  const trimmed = userId.trim();
  if (!trimmed) return false;
  const res = await pool.query<{ note: string }>(`SELECT note FROM users WHERE id = $1`, [trimmed]);
  return isPremiumRevokeLocked(res.rows[0]?.note);
}

export async function setUserPremiumUntilMs(userId: string, premiumUntilMs: number | null): Promise<boolean> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  const trimmed = userId.trim();
  if (!trimmed) return false;
  const res = await pool.query(
    `UPDATE users
     SET premium_until_ms = $2, updated_at = now()
     WHERE id = $1`,
    [trimmed, premiumUntilMs],
  );
  return (res.rowCount ?? 0) > 0;
}

export async function getUserPremiumRecord(userId: string): Promise<{
  userExists: boolean;
  premiumUntilMs: number | null;
  note: string;
}> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  const trimmed = userId.trim();
  if (!trimmed) return { userExists: false, premiumUntilMs: null, note: '' };
  const res = await pool.query<{ premium_until_ms: string | null; note: string | null }>(
    `SELECT premium_until_ms, note FROM users WHERE id = $1`,
    [trimmed],
  );
  const row = res.rows[0];
  if (!row) return { userExists: false, premiumUntilMs: null, note: '' };

  const raw = row.premium_until_ms != null ? Number(row.premium_until_ms) : null;
  return {
    userExists: true,
    premiumUntilMs: raw,
    note: String(row.note ?? ''),
  };
}
