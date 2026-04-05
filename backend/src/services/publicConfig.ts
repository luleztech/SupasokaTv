import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';

/** Mirrors SupaAdmin `AppConfig` content fields (+ ok wrapper in route). */
export async function fetchPublicConfig(): Promise<Record<string, unknown>> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured on the API service', 'NO_DATABASE');
  }

  const [chRes, carRes, malRes, liveRes, pkgRes, setRes] = await Promise.all([
    pool.query(
      `SELECT id, name, cat, img, free, viewers,
              stream_url AS "streamUrl",
              enabled, drm,
              clear_key_kid_key AS "clearKeyKidKey",
              sort_order AS "sortOrder"
       FROM channels ORDER BY sort_order, id`,
    ),
    pool.query(
      `SELECT id, badge, badge_icon AS "badgeIcon", title,
              channel_id AS "channelId", img,
              sort_order AS "sortOrder"
       FROM carousel_slides ORDER BY sort_order, id`,
    ),
    pool.query(
      `SELECT id, label, price_lines AS "priceLines", amount, period, popular,
              accent1, accent2, badge,
              sort_order AS "sortOrder"
       FROM malipo_plans ORDER BY sort_order, id`,
    ),
    pool.query(
      `SELECT id, title, sport, sport_icon AS "sportIcon", img,
              channel_id AS "channelId", live_badge AS "liveBadge",
              sort_order AS "sortOrder"
       FROM live_matches ORDER BY sort_order, id`,
    ),
    pool.query(
      `SELECT id, name, price, period, features, popular,
              sort_order AS "sortOrder"
       FROM premium_packages ORDER BY sort_order, id`,
    ),
    pool.query(`SELECT key, value FROM app_settings`),
  ]);

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

  return {
    configVersion: 1,
    customerCareWhatsapp: settings.customerCareWhatsapp ?? '212600000000',
    channels,
    carousel: carRes.rows,
    malipoPlans: malRes.rows,
    liveMatches: liveRes.rows,
    premiumPackages: pkgRes.rows,
  };
}
