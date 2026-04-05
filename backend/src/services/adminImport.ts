import { DatabaseError } from 'pg';

import { getPool } from '../db/pool';
import { logger } from '../lib/logger';
import { HttpError } from '../middleware/errorHandler';

type ChannelIn = {
  id: number;
  name: string;
  cat: string;
  img: string;
  free: boolean;
  viewers: string;
  url?: string;
  streamUrl?: string;
  enabled?: boolean;
  drm?: string;
  clearKeyKidKey?: string;
};

function digitsWhatsapp(raw: unknown): string {
  const s = String(raw ?? '').replace(/\D/g, '');
  if (s.length >= 8 && s.length <= 15) return s;
  return '212600000000';
}

function importErrorMessage(e: unknown): string {
  if (e instanceof DatabaseError) {
    const parts = [e.message];
    if (e.detail) parts.push(e.detail);
    if (e.hint) parts.push(`Hint: ${e.hint}`);
    return parts.join(' ');
  }
  if (e instanceof Error) return e.message;
  return String(e);
}

/** Dart `Color.value` is 32-bit ARGB (>2^31-1); PG INTEGER must stay ≤ 2147483647. Keep RGB only. */
function accentRgbFromDartColor(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) return 0;
  const u = Math.trunc(n) >>> 0;
  return u & 0xffffff;
}

export async function importAppConfig(body: unknown): Promise<void> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  if (!body || typeof body !== 'object') {
    throw new HttpError(400, 'Invalid JSON body', 'BAD_REQUEST');
  }
  const b = body as Record<string, unknown>;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `TRUNCATE carousel_slides, live_matches, malipo_plans, premium_packages, channels RESTART IDENTITY CASCADE`,
    );

    const channels = (b.channels as unknown[]) ?? [];
    const channelIds = new Set<number>();
    let sort = 0;
    for (const c of channels) {
      const ch = c as ChannelIn;
      channelIds.add(ch.id);
      const streamUrl = String(ch.streamUrl ?? ch.url ?? '');
      await client.query(
        `INSERT INTO channels (id, name, cat, img, free, viewers, stream_url, enabled, drm, clear_key_kid_key, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
        [
          ch.id,
          ch.name,
          ch.cat,
          ch.img ?? '',
          ch.free ?? true,
          ch.viewers ?? '',
          streamUrl,
          ch.enabled ?? true,
          ch.drm ?? 'none',
          ch.clearKeyKidKey ?? '',
          sort,
        ],
      );
      sort += 1;
    }
    await client.query(
      `SELECT setval(pg_get_serial_sequence('channels','id'), (SELECT COALESCE(MAX(id),1) FROM channels))`,
    );

    const fallbackChannelId =
      channels.length > 0 ? (channels[0] as ChannelIn).id : null;

    const carousel = (b.carousel as unknown[]) ?? [];
    if (carousel.length > 0 && fallbackChannelId === null) {
      throw new HttpError(400, 'Carousel slides require at least one channel.', 'NO_CHANNELS');
    }
    sort = 0;
    for (const s of carousel) {
      const x = s as Record<string, unknown>;
      const rawCid = Number(x.channelId);
      const channelId =
        channelIds.has(rawCid) && Number.isFinite(rawCid)
          ? rawCid
          : fallbackChannelId!;
      await client.query(
        `INSERT INTO carousel_slides (badge, badge_icon, title, channel_id, img, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [x.badge, x.badgeIcon, x.title, channelId, x.img, sort],
      );
      sort += 1;
    }

    const lives = (b.liveMatches as unknown[]) ?? [];
    sort = 0;
    for (const m of lives) {
      const x = m as Record<string, unknown>;
      const rawLc = Number(x.channelId);
      const liveChannelId =
        channelIds.has(rawLc) && Number.isFinite(rawLc) ? rawLc : null;
      await client.query(
        `INSERT INTO live_matches (id, title, sport, sport_icon, img, channel_id, live_badge, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [
          x.id,
          x.title,
          (x.sport as string) ?? '',
          (x.sportIcon as string) ?? '',
          (x.img as string) ?? '',
          liveChannelId,
          (x.liveBadge as boolean) ?? true,
          sort,
        ],
      );
      sort += 1;
    }
    await client.query(
      `SELECT setval(pg_get_serial_sequence('live_matches','id'), (SELECT COALESCE(MAX(id),1) FROM live_matches))`,
    );

    const mal = (b.malipoPlans as unknown[]) ?? [];
    sort = 0;
    for (const m of mal) {
      const x = m as Record<string, unknown>;
      await client.query(
        `INSERT INTO malipo_plans (id, label, price_lines, amount, period, popular, accent1, accent2, badge, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
        [
          x.id,
          x.label,
          x.priceLines,
          x.amount,
          x.period,
          (x.popular as boolean) ?? false,
          accentRgbFromDartColor(x.accent1),
          accentRgbFromDartColor(x.accent2),
          (x.badge as string) ?? '',
          sort,
        ],
      );
      sort += 1;
    }

    const pkgs = (b.premiumPackages as unknown[]) ?? [];
    sort = 0;
    for (const p of pkgs) {
      const x = p as Record<string, unknown>;
      const features = Array.isArray(x.features) ? x.features : [];
      await client.query(
        `INSERT INTO premium_packages (id, name, price, period, features, popular, sort_order)
         VALUES ($1,$2,$3,$4,$5::jsonb,$6,$7)`,
        [x.id, x.name, x.price, x.period, JSON.stringify(features), (x.popular as boolean) ?? false, sort],
      );
      sort += 1;
    }

    const wa = digitsWhatsapp(b.customerCareWhatsapp);
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('customerCareWhatsapp', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [wa],
    );

    const cfgVer =
      typeof b.configVersion === 'number' && Number.isFinite(b.configVersion)
        ? String(Math.trunc(b.configVersion))
        : '1';
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('configVersion', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [cfgVer],
    );

    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('configSyncedAt', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [String(Date.now())],
    );

    const appUsers = (b.users as unknown[]) ?? [];
    for (const u of appUsers) {
      const x = u as Record<string, unknown>;
      const uid = String(x.id ?? '').trim();
      if (!uid) continue;
      const premiumRaw = x.premiumUntilMs;
      const premiumUntilMs =
        premiumRaw === null || premiumRaw === undefined ? null : Number(premiumRaw);
      await client.query(
        `INSERT INTO users (id, profile_username, legacy_user_id, premium_until_ms, note, updated_at)
         VALUES ($1, $2, $3, $4, $5, now())
         ON CONFLICT (id) DO UPDATE SET
           profile_username = EXCLUDED.profile_username,
           legacy_user_id = COALESCE(EXCLUDED.legacy_user_id, users.legacy_user_id),
           premium_until_ms = EXCLUDED.premium_until_ms,
           note = EXCLUDED.note,
           updated_at = now()`,
        [
          uid,
          String(x.username ?? ''),
          x.legacyUserId != null ? String(x.legacyUserId) : null,
          premiumUntilMs != null && Number.isFinite(premiumUntilMs) ? Math.trunc(premiumUntilMs) : null,
          String(x.note ?? ''),
        ],
      );
    }

    await client.query(`DELETE FROM users WHERE id ~ '^usr_demo'`);

    await client.query('COMMIT');
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch {
      /* ignore */
    }
    if (e instanceof HttpError) {
      throw e;
    }
    logger.error({ err: e }, 'admin_import_failed');
    throw new HttpError(500, importErrorMessage(e), 'IMPORT_FAILED');
  } finally {
    client.release();
  }
}
