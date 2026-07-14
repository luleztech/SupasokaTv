import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';

const publicIdRe = /^User-[A-Za-z2-9]{5}$/;

export function isValidPublicUserId(id: string): boolean {
  return publicIdRe.test(id);
}

/** First open or returning viewer — upsert in `users` (no admin key). */
export async function registerPublicUser(body: unknown): Promise<void> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  if (!body || typeof body !== 'object') {
    throw new HttpError(400, 'Invalid JSON body', 'BAD_REQUEST');
  }
  const b = body as Record<string, unknown>;
  const publicId = String(b.publicId ?? '').trim();
  if (!isValidPublicUserId(publicId)) {
    throw new HttpError(400, 'publicId must match User-XXXXX (5 chars A–Z, a–z, 2–9)', 'BAD_PUBLIC_ID');
  }
  let profileUsername = String(b.profileUsername ?? '').trim();
  if (profileUsername.length === 0) profileUsername = publicId;
  if (profileUsername.length > 160) profileUsername = profileUsername.slice(0, 160);

  let legacyUserId = String(b.legacyUserId ?? b.userNumber ?? b.phone ?? b.buyerPhone ?? '').trim();

  await pool.query(
    `INSERT INTO users (id, profile_username, legacy_user_id, premium_until_ms, note, updated_at)
     VALUES ($1, $2, NULLIF($3, ''), NULL, '', now())
     ON CONFLICT (id) DO UPDATE SET
       profile_username = EXCLUDED.profile_username,
       legacy_user_id = COALESCE(EXCLUDED.legacy_user_id, users.legacy_user_id),
       updated_at = now()`,
    [publicId, profileUsername, legacyUserId],
  );
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
  const { ensurePaymentIntentsTable } = await import('./paymentIntents');
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
