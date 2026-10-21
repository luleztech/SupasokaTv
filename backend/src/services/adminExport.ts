import { getPool } from '../db/pool';
import { ensureChannelPlaybackHeaderColumns } from '../db/channelPlaybackHeaders';
import { jsonSafe } from '../lib/jsonSafe';
import { logger } from '../lib/logger';
import { normalizeStreamUrl } from '../lib/streamUrl';
import { HttpError } from '../middleware/errorHandler';
import { buildAppUpdatePayload } from './appUpdatePolicy';

function asText(value: unknown, fallback = ''): string {
  if (value == null) return fallback;
  return String(value);
}

function asBool(value: unknown, fallback = false): boolean {
  if (typeof value === 'boolean') return value;
  if (value === 't' || value === 'true' || value === 1 || value === '1') return true;
  if (value === 'f' || value === 'false' || value === 0 || value === '0') return false;
  return fallback;
}

function asInt(value: unknown, fallback = 0): number {
  if (typeof value === 'bigint') return Number(value);
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function asStringList(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((item) => String(item));
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value) as unknown;
      if (Array.isArray(parsed)) return parsed.map((item) => String(item));
    } catch {
      return [];
    }
  }
  return [];
}

function asIso(value: unknown): string | null {
  if (value instanceof Date) {
    const n = value.getTime();
    return Number.isFinite(n) ? value.toISOString() : null;
  }
  if (typeof value === 'string' && value.trim()) {
    const n = Date.parse(value);
    return Number.isFinite(n) ? new Date(n).toISOString() : value;
  }
  return null;
}

function isTransientDbError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return /timeout|ECONNRESET|ECONNREFUSED|Connection terminated|too many clients|sorry, too many clients/i.test(
    message,
  );
}

async function loadAdminExport(): Promise<Record<string, unknown>> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }

  await ensureChannelPlaybackHeaderColumns(pool);
  const client = await pool.connect();
  try {
    const channelsRes = await client.query(
      `SELECT id, name, cat, img, free, viewers, stream_url, enabled, drm,
              clear_key_kid_key, audio_language, referer, origin, user_agent
       FROM channels ORDER BY sort_order, id`,
    );
    const carouselRes = await client.query(
      `SELECT id, badge, badge_icon, title, channel_id, img
       FROM carousel_slides ORDER BY sort_order, id`,
    );
    const malRes = await client.query(
      `SELECT id, label, price_lines, amount, period, popular, accent1, accent2, badge
       FROM malipo_plans ORDER BY sort_order, id`,
    );
    const liveRes = await client.query(
      `SELECT id, title, sport, sport_icon, img, channel_id, live_badge, match_time
       FROM live_matches ORDER BY sort_order, id`,
    );
    const pkgRes = await client.query(
      `SELECT id, name, price, period, features, popular
       FROM premium_packages ORDER BY sort_order, id`,
    );
    const setRes = await client.query(`SELECT key, value FROM app_settings`);
    const notifRes = await client.query(
      `SELECT id, title, body, target, created_at, scheduled_for
       FROM notifications
       ORDER BY created_at DESC
       LIMIT 80`,
    );
    const usersRes = await client.query(
      `SELECT id, profile_username, legacy_user_id, premium_until_ms, note, created_at
       FROM users
       ORDER BY created_at DESC`,
    );

    const settings: Record<string, string> = {};
    for (const row of setRes.rows as { key: string; value: string }[]) {
      settings[row.key] = row.value ?? '';
    }
    const configVersion = asInt(settings.configVersion, 1) || 1;
    const syncedAt = settings.configSyncedAt ? asInt(settings.configSyncedAt, 0) : 0;
    const forceUpdateEnabled =
      settings.forceUpdateEnabled === 'true' || settings.forceUpdateEnabled === '1';
    const users = (usersRes.rows as Record<string, unknown>[]).map((row) => {
      const created = asIso(row.created_at);
      const premiumRaw = row.premium_until_ms;
      return {
        id: asText(row.id),
        username: asText(row.profile_username) || asText(row.id),
        userNumber:
          row.legacy_user_id == null || asText(row.legacy_user_id) === ''
            ? null
            : asText(row.legacy_user_id),
        premiumUntilMs: premiumRaw == null || premiumRaw === '' ? null : asInt(premiumRaw, 0),
        note: asText(row.note),
        createdAtMs: created ? Date.parse(created) : 0,
      };
    });

    const channels = (channelsRes.rows as Record<string, unknown>[]).map((row) => {
      const streamUrl = normalizeStreamUrl(row.stream_url);
      return {
        id: asInt(row.id),
        name: asText(row.name),
        cat: asText(row.cat, 'movies'),
        img: asText(row.img),
        free: asBool(row.free, false),
        viewers: asText(row.viewers),
        streamUrl,
        url: streamUrl,
        stream_url: streamUrl,
        enabled: asBool(row.enabled, true),
        drm: asText(row.drm, 'none'),
        clearKeyKidKey: asText(row.clear_key_kid_key),
        audioLanguage: asText(row.audio_language, 'sw'),
        referer: asText(row.referer),
        origin: asText(row.origin),
        userAgent: asText(row.user_agent),
      };
    });

    const appUpdate = buildAppUpdatePayload(settings);

    return jsonSafe({
      configVersion,
      ...(syncedAt > 0 ? { configSyncedAt: syncedAt } : {}),
      customerCareWhatsapp: settings.customerCareWhatsapp ?? '212600000000',
      channels,
      carousel: (carouselRes.rows as Record<string, unknown>[]).map((row) => ({
        id: asText(row.id),
        badge: asText(row.badge),
        badgeIcon: asText(row.badge_icon),
        title: asText(row.title),
        channelId: asInt(row.channel_id),
        img: asText(row.img),
      })),
      malipoPlans: (malRes.rows as Record<string, unknown>[]).map((row) => ({
        id: asText(row.id),
        label: asText(row.label),
        priceLines: asText(row.price_lines),
        amount: asText(row.amount),
        period: asText(row.period),
        popular: asBool(row.popular, false),
        accent1: asInt(row.accent1, 0x0ea5e9),
        accent2: asInt(row.accent2, 0x6366f1),
        badge: asText(row.badge),
      })),
      liveMatches: (liveRes.rows as Record<string, unknown>[]).map((row) => ({
        id: asInt(row.id),
        title: asText(row.title),
        sport: asText(row.sport),
        sportIcon: asText(row.sport_icon),
        img: asText(row.img),
        channelId: asInt(row.channel_id),
        liveBadge: asBool(row.live_badge, true),
        matchTime: row.match_time == null ? null : asText(row.match_time),
      })),
      premiumPackages: (pkgRes.rows as Record<string, unknown>[]).map((row) => ({
        id: asText(row.id),
        name: asText(row.name),
        price: asText(row.price),
        period: asText(row.period),
        features: asStringList(row.features),
        popular: asBool(row.popular, false),
      })),
      forceUpdateEnabled,
      minAndroidBuild: appUpdate.minBuild,
      minAndroidVersion: appUpdate.minVersion,
      latestAndroidVersion: appUpdate.latestVersion,
      latestAndroidBuild: appUpdate.latestBuild,
      playStoreUrl: appUpdate.playStoreUrl,
      notificationLog: (notifRes.rows as Record<string, unknown>[]).map((row) => ({
        id: asText(row.id),
        title: asText(row.title),
        body: asText(row.body),
        target: asText(row.target, 'all'),
        createdAt: asIso(row.created_at) ?? new Date(0).toISOString(),
        scheduledFor: asIso(row.scheduled_for),
      })),
      users,
    }) as Record<string, unknown>;
  } finally {
    client.release();
  }
}

/** Full AppConfig for SupaAdmin. One database connection, real stream links included. */
export async function fetchAdminExportConfig(): Promise<Record<string, unknown>> {
  try {
    return await loadAdminExport();
  } catch (err) {
    if (!isTransientDbError(err)) {
      logger.error({ err }, 'admin_export_failed');
      if (err instanceof HttpError) throw err;
      throw new HttpError(503, 'Imeshindwa kupakia mipangilio. Jaribu tena.', 'EXPORT_FAILED');
    }
    try {
      return await loadAdminExport();
    } catch (again) {
      logger.error({ err: again }, 'admin_export_failed');
      if (again instanceof HttpError) throw again;
      throw new HttpError(503, 'Imeshindwa kupakia mipangilio. Jaribu tena.', 'EXPORT_FAILED');
    }
  }
}
