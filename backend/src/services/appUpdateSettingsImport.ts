import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';

const DEFAULT_PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.ayubu.supasoka';

export type AppUpdateSettingsInput = {
  forceUpdateEnabled?: boolean;
  minAndroidBuild?: number;
  minAndroidVersion?: string;
  latestAndroidVersion?: string;
  latestAndroidBuild?: number;
  playStoreUrl?: string;
};

function parsePositiveInt(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.trunc(n);
}

/** Fast path: update only app-update keys in `app_settings` (no full catalog import). */
export async function importAppUpdateSettings(body: AppUpdateSettingsInput): Promise<void> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured on the API service', 'NO_DATABASE');
  }

  const minBuild = parsePositiveInt(body.minAndroidBuild);
  const minVer = String(body.minAndroidVersion ?? '').trim();
  const latestVer = String(body.latestAndroidVersion ?? '').trim();
  const latestBuild = parsePositiveInt(body.latestAndroidBuild);
  const forceUpdate = body.forceUpdateEnabled === true ? 'true' : 'false';
  const playUrl = String(body.playStoreUrl ?? '').trim() || DEFAULT_PLAY_STORE_URL;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('minAndroidBuild', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [String(minBuild)],
    );
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('minAndroidVersion', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [minVer],
    );
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('latestAndroidVersion', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [latestVer],
    );
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('latestAndroidBuild', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [String(latestBuild)],
    );
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('forceUpdateEnabled', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [forceUpdate],
    );
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('playStoreUrl', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [playUrl],
    );
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}
