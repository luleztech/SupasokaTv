import { getPool } from '../db/pool';
import { jsonSafe } from '../lib/jsonSafe';
import { HttpError } from '../middleware/errorHandler';
import { fetchPublicConfig } from './publicConfig';
import { buildAppUpdatePayload, fetchAppUpdateSettings } from './appUpdatePolicy';
import { listUsersForAdmin } from './userDirectory';

/** Full `AppConfig`-shaped JSON for SupaAdmin (same fields as `POST /admin/import` body). */
export async function fetchAdminExportConfig(): Promise<Record<string, unknown>> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }

  const [base, users, notifRes, updateSettings] = await Promise.all([
    fetchPublicConfig(),
    listUsersForAdmin(),
    pool.query(
      `SELECT id, title, body, target, created_at, scheduled_for
       FROM notifications
       ORDER BY created_at DESC
       LIMIT 500`,
    ),
    fetchAppUpdateSettings(),
  ]);

  const appUpdate = buildAppUpdatePayload(updateSettings);
  const forceUpdateEnabled =
    updateSettings.forceUpdateEnabled === 'true' || updateSettings.forceUpdateEnabled === '1';

  const notificationLog = (notifRes.rows as Record<string, unknown>[]).map((row) => {
    const created = row.created_at as Date | string | undefined;
    const createdAt =
      created instanceof Date
        ? created.toISOString()
        : typeof created === 'string'
          ? created
          : new Date().toISOString();
    const sched = row.scheduled_for as Date | string | null | undefined;
    return {
      id: String(row.id ?? ''),
      title: String(row.title ?? ''),
      body: String(row.body ?? ''),
      target: String(row.target ?? 'all'),
      createdAt,
      scheduledFor:
        sched == null
          ? null
          : sched instanceof Date
            ? sched.toISOString()
            : String(sched),
    };
  });

  return jsonSafe({
    ...base,
    forceUpdateEnabled,
    minAndroidBuild: appUpdate.minBuild,
    minAndroidVersion: appUpdate.minVersion,
    latestAndroidVersion: appUpdate.latestVersion,
    latestAndroidBuild: appUpdate.latestBuild,
    playStoreUrl: appUpdate.playStoreUrl,
    notificationLog,
    users,
  }) as Record<string, unknown>;
}
