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
  audioLanguage?: string;
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

function asString(raw: unknown, fallback = ''): string {
  if (raw === null || raw === undefined) return fallback;
  return String(raw);
}

function asInt(raw: unknown): number | null {
  const n = Number(raw);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function asBool(raw: unknown, fallback: boolean): boolean {
  if (raw === true || raw === false) return raw;
  const s = String(raw ?? '').trim().toLowerCase();
  if (s === 'false' || s === '0' || s === 'no') return false;
  if (s === 'true' || s === '1' || s === 'yes') return true;
  return fallback;
}

/** ISO 639-1 audio preference for playback: `sw` (default) | `en`. */
function normalizeChannelAudioLanguage(raw: unknown): string {
  const r = String(raw ?? '').trim().toLowerCase();
  if (r === 'en' || r.startsWith('en-') || r === 'english' || r === 'eng') return 'en';
  if (r === 'sw' || r.startsWith('sw-') || r === 'swahili' || r === 'kiswahili' || r === 'swa') return 'sw';
  return 'sw';
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
      const channelId = asInt(ch.id);
      if (channelId === null) {
        throw new HttpError(400, 'Channel id must be a number', 'BAD_CHANNEL_ID');
      }
      channelIds.add(channelId);
      const streamUrl = asString(ch.streamUrl ?? ch.url, '');
      await client.query(
        `INSERT INTO channels (id, name, cat, img, free, viewers, stream_url, enabled, drm, clear_key_kid_key, audio_language, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
        [
          channelId,
          asString(ch.name, ''),
          asString(ch.cat, 'movies'),
          asString(ch.img, ''),
          asBool(ch.free, true),
          asString(ch.viewers, ''),
          streamUrl,
          asBool(ch.enabled, true),
          asString(ch.drm, 'none'),
          asString(ch.clearKeyKidKey, ''),
          normalizeChannelAudioLanguage(ch.audioLanguage),
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
      const rawCid = asInt(x.channelId);
      const channelId =
        rawCid !== null && channelIds.has(rawCid) ? rawCid : fallbackChannelId!;
      await client.query(
        `INSERT INTO carousel_slides (badge, badge_icon, title, channel_id, img, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [asString(x.badge, ''), asString(x.badgeIcon, ''), asString(x.title, ''), channelId, asString(x.img, ''), sort],
      );
      sort += 1;
    }

    const lives = (b.liveMatches as unknown[]) ?? [];
    sort = 0;
    for (const m of lives) {
      const x = m as Record<string, unknown>;
      const rawId = asInt(x.id);
      const rawLc = asInt(x.channelId);
      const liveChannelId = rawLc !== null && channelIds.has(rawLc) ? rawLc : null;
      if (rawId === null) {
        throw new HttpError(400, 'Live match id must be a number', 'BAD_LIVE_ID');
      }
      await client.query(
        `INSERT INTO live_matches (id, title, sport, sport_icon, img, channel_id, live_badge, sort_order, match_time)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [
          rawId,
          asString(x.title, ''),
          asString(x.sport, ''),
          asString(x.sportIcon, ''),
          asString(x.img, ''),
          liveChannelId,
          asBool(x.liveBadge, true),
          sort,
          asString(x.matchTime, ''),
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
          asString(x.id, ''),
          asString(x.label, ''),
          asString(x.priceLines, ''),
          asString(x.amount, ''),
          asString(x.period, ''),
          asBool(x.popular, false),
          accentRgbFromDartColor(x.accent1),
          accentRgbFromDartColor(x.accent2),
          asString(x.badge, ''),
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
        [
          asString(x.id, ''),
          asString(x.name, ''),
          asString(x.price, ''),
          asString(x.period, ''),
          JSON.stringify(features),
          asBool(x.popular, false),
          sort,
        ],
      );
      sort += 1;
    }

    const wa = digitsWhatsapp(b.customerCareWhatsapp);
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('customerCareWhatsapp', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [wa],
    );

    const minBuildRaw = Number((b as Record<string, unknown>).minAndroidBuild);
    const minBuild =
      Number.isFinite(minBuildRaw) && minBuildRaw > 0 ? Math.trunc(minBuildRaw) : 0;
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('minAndroidBuild', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [String(minBuild)],
    );

    const minVer = String((b as Record<string, unknown>).minAndroidVersion ?? '').trim();
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('minAndroidVersion', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [minVer],
    );

    const latestVer = String((b as Record<string, unknown>).latestAndroidVersion ?? '').trim();
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('latestAndroidVersion', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [latestVer],
    );

    const latestBuildRaw = Number((b as Record<string, unknown>).latestAndroidBuild);
    const latestBuild =
      Number.isFinite(latestBuildRaw) && latestBuildRaw > 0 ? Math.trunc(latestBuildRaw) : 0;
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('latestAndroidBuild', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [String(latestBuild)],
    );

    const forceUpdate = (b as Record<string, unknown>).forceUpdateEnabled === true ? 'true' : 'false';
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('forceUpdateEnabled', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [forceUpdate],
    );

    const playUrl = String((b as Record<string, unknown>).playStoreUrl ?? '').trim();
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('playStoreUrl', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [
        playUrl || 'https://play.google.com/store/apps/details?id=com.ayubu.supasoka',
      ],
    );

    const verRow = await client.query(`SELECT value FROM app_settings WHERE key = 'configVersion'`);
    let nextVer = 1;
    const rawV = verRow.rows[0]?.value;
    if (rawV != null && rawV !== '') {
      const n = parseInt(String(rawV), 10);
      if (Number.isFinite(n) && n > 0) nextVer = n + 1;
    }
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('configVersion', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [String(nextVer)],
    );

    const syncedMs = String(Date.now());
    await client.query(
      `INSERT INTO app_settings (key, value) VALUES ('configSyncedAt', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [syncedMs],
    );

    const appUsers = (b.users as unknown[]) ?? [];
    for (const u of appUsers) {
      const x = u as Record<string, unknown>;
      const uid = String(x.id ?? '').trim();
      if (!uid) continue;
      const premiumRaw = x.premiumUntilMs;
      const premiumUntilMs =
        premiumRaw === null || premiumRaw === undefined ? null : Number(premiumRaw);
      const profileUser = String(x.username ?? '').trim();
      const displayName = profileUser.length > 0 ? profileUser : uid;
      const legacyUserId = x.userNumber != null
        ? String(x.userNumber)
        : x.legacyUserId != null
          ? String(x.legacyUserId)
          : null;
      await client.query(
        `INSERT INTO users (id, profile_username, legacy_user_id, premium_until_ms, note, updated_at)
         VALUES ($1, $2, $3, $4, $5, now())
         ON CONFLICT (id) DO UPDATE SET
           profile_username = COALESCE(NULLIF(TRIM(EXCLUDED.profile_username), ''), users.profile_username),
           legacy_user_id = COALESCE(EXCLUDED.legacy_user_id, users.legacy_user_id),
           premium_until_ms = COALESCE(EXCLUDED.premium_until_ms, users.premium_until_ms),
           note = EXCLUDED.note,
           updated_at = now()`,
        [
          uid,
          displayName,
          legacyUserId,
          premiumUntilMs != null && Number.isFinite(premiumUntilMs) ? Math.trunc(premiumUntilMs) : null,
          String(x.note ?? ''),
        ],
      );
    }

    /** Do not delete viewers registered via `POST /public/register-user` — only remove users with `DELETE /admin/users/:id`. */

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
