import type { QueryResult } from 'pg';

import { getPool } from '../db/pool';
import { jsonSafe } from '../lib/jsonSafe';
import { logger } from '../lib/logger';
import { HttpError } from '../middleware/errorHandler';

async function tagQuery<T extends QueryResult>(label: string, run: () => Promise<T>): Promise<T> {
  try {
    return await run();
  } catch (err) {
    const extra: Record<string, unknown> = { label };
    if (err && typeof err === 'object') {
      const e = err as { code?: string; detail?: string; hint?: string; message?: string };
      if (e.code != null) extra.pgCode = e.code;
      if (e.detail != null) extra.pgDetail = e.detail;
      if (e.hint != null) extra.pgHint = e.hint;
      if (e.message != null) extra.pgMessage = e.message;
    }
    logger.error({ err, ...extra }, 'fetchPublicConfig_query_failed');
    throw err;
  }
}

/** Mirrors SupaAdmin `AppConfig` content fields (+ ok wrapper in route). */
export async function fetchPublicConfig(): Promise<Record<string, unknown>> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured on the API service', 'NO_DATABASE');
  }

  let chRes, carRes, malRes, liveRes, pkgRes, setRes;
  try {
    [chRes, carRes, malRes, liveRes, pkgRes, setRes] = await Promise.all([
      tagQuery('channels', () =>
        pool.query(
          `SELECT id, name, cat, img, free, viewers,
                  stream_url AS "streamUrl",
                  enabled, drm,
                  clear_key_kid_key AS "clearKeyKidKey",
                  sort_order AS "sortOrder"
           FROM channels ORDER BY sort_order, id`,
        ),
      ),
      tagQuery('carousel_slides', () =>
        pool.query(
          `SELECT id, badge, badge_icon AS "badgeIcon", title,
                  channel_id AS "channelId", img,
                  sort_order AS "sortOrder"
           FROM carousel_slides ORDER BY sort_order, id`,
        ),
      ),
      tagQuery('malipo_plans', () =>
        pool.query(
          `SELECT id, label, price_lines AS "priceLines", amount, period, popular,
                  accent1, accent2, badge,
                  sort_order AS "sortOrder"
           FROM malipo_plans ORDER BY sort_order, id`,
        ),
      ),
      tagQuery('live_matches', () =>
        pool.query(
          `SELECT lm.id, lm.title, lm.sport, lm.sport_icon AS "sportIcon", lm.img,
                  lm.channel_id AS "channelId", lm.live_badge AS "liveBadge",
                  lm.match_time AS "matchTime",
                  lm.sort_order AS "sortOrder"
           FROM live_matches lm
           INNER JOIN channels c ON c.id = lm.channel_id
           WHERE c.enabled = TRUE
             AND NULLIF(TRIM(c.stream_url), '') IS NOT NULL
           ORDER BY lm.sort_order, lm.id`,
        ),
      ),
      tagQuery('premium_packages', () =>
        pool.query(
          `SELECT id, name, price, period, features, popular,
                  sort_order AS "sortOrder"
           FROM premium_packages ORDER BY sort_order, id`,
        ),
      ),
      tagQuery('app_settings', () => pool.query(`SELECT key, value FROM app_settings`)),
    ]);
  } catch {
    throw new HttpError(503, 'Could not read configuration from the database', 'CONFIG_DB');
  }

  const settings: Record<string, string> = {};
  for (const row of setRes.rows as { key: string; value: string }[]) {
    settings[row.key] = row.value;
  }

  const channels = (chRes.rows as Record<string, unknown>[]).map((row) => {
    const streamUrl = String(row.streamUrl ?? '');
    return {
      ...row,
      url: streamUrl,
    };
  });

  const cv = Number(settings.configVersion);
  const syncedAt =
    settings.configSyncedAt != null && settings.configSyncedAt !== ''
      ? Number(settings.configSyncedAt)
      : null;

  // Strip bigint (e.g. malipo accent BIGINT) so Express res.json never throws.
  return jsonSafe({
    configVersion: Number.isFinite(cv) && cv > 0 ? cv : 1,
    ...(syncedAt != null && Number.isFinite(syncedAt) ? { configSyncedAt: syncedAt } : {}),
    customerCareWhatsapp: settings.customerCareWhatsapp ?? '212600000000',
    channels,
    carousel: carRes.rows,
    malipoPlans: malRes.rows,
    liveMatches: liveRes.rows,
    premiumPackages: pkgRes.rows,
  }) as Record<string, unknown>;
}

/** Tiny payload for viewer poll — compares `configSyncedAt` without loading channels/media rows. */
export async function fetchPublicConfigMeta(): Promise<{
  configVersion: number;
  configSyncedAt: number | null;
}> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured on the API service', 'NO_DATABASE');
  }
  const setRes = await pool.query(
    `SELECT key, value FROM app_settings WHERE key IN ('configVersion', 'configSyncedAt')`,
  );
  const settings: Record<string, string> = {};
  for (const row of setRes.rows as { key: string; value: string }[]) {
    settings[row.key] = row.value;
  }
  const cv = Number(settings.configVersion);
  const syncedRaw = settings.configSyncedAt;
  const syncedAt =
    syncedRaw != null && syncedRaw !== '' ? Number(syncedRaw) : null;
  return {
    configVersion: Number.isFinite(cv) && cv > 0 ? cv : 1,
    configSyncedAt: syncedAt != null && Number.isFinite(syncedAt) ? syncedAt : null,
  };
}
