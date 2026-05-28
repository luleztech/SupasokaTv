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
  const res = await pool.query(`DELETE FROM users WHERE id = $1`, [trimmed]);
  return (res.rowCount ?? 0) > 0;
}

export async function getUserPremiumStatus(userId: string): Promise<number | null> {
  const row = await getUserPremiumRecord(userId);
  return row.premiumUntilMs;
}

export async function getUserPremiumRecord(userId: string): Promise<{ userExists: boolean; premiumUntilMs: number | null }> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  const trimmed = userId.trim();
  if (!trimmed) return { userExists: false, premiumUntilMs: null };
  const res = await pool.query<{ premium_until_ms: string | null }>(
    `SELECT premium_until_ms FROM users WHERE id = $1`,
    [trimmed],
  );
  const row = res.rows[0];
  if (!row) return { userExists: false, premiumUntilMs: null };
  return {
    userExists: true,
    premiumUntilMs: row.premium_until_ms != null ? Number(row.premium_until_ms) : null,
  };
}
