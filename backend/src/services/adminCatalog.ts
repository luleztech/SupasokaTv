import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import {
  accentRgbFromDartColor,
  asBool,
  asInt,
  asString,
  normalizeChannelAudioLanguage,
} from './adminImportHelpers';

type ChannelBody = {
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

function requirePool() {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
  }
  return pool;
}

function parseChannel(raw: unknown): ChannelBody {
  if (!raw || typeof raw !== 'object') {
    throw new HttpError(400, 'Invalid channel body', 'BAD_CHANNEL');
  }
  const c = raw as Record<string, unknown>;
  const id = asInt(c.id);
  if (id === null) {
    throw new HttpError(400, 'Channel id must be a number', 'BAD_CHANNEL_ID');
  }
  // Admin Flutter sends `url`; some clients send `streamUrl`. Prefer any non-empty value.
  // Do NOT use `??` alone — empty string would shadow a valid `url` and wipe the DB.
  const streamUrl = [c.streamUrl, c.url, c.stream_url]
    .map((v) => asString(v, '').trim())
    .find((s) => s.length > 0) ?? '';
  return {
    id,
    name: asString(c.name, ''),
    cat: asString(c.cat, 'movies'),
    img: asString(c.img, ''),
    free: asBool(c.free, true),
    viewers: asString(c.viewers, ''),
    url: streamUrl,
    streamUrl,
    enabled: asBool(c.enabled, true),
    drm: asString(c.drm, 'none'),
    clearKeyKidKey: asString(c.clearKeyKidKey, ''),
    audioLanguage: normalizeChannelAudioLanguage(c.audioLanguage),
  };
}

export async function upsertChannelFast(body: unknown): Promise<void> {
  const ch = parseChannel(body);
  const pool = requirePool();
  const streamUrl = ch.streamUrl || ch.url || '';
  const existing = await pool.query(`SELECT id FROM channels WHERE id = $1`, [ch.id]);
  if (existing.rowCount && existing.rowCount > 0) {
    await pool.query(
      `UPDATE channels
       SET name = $2, cat = $3, img = $4, free = $5, viewers = $6, stream_url = $7,
           enabled = $8, drm = $9, clear_key_kid_key = $10, audio_language = $11
       WHERE id = $1`,
      [
        ch.id,
        ch.name,
        ch.cat,
        ch.img,
        ch.free,
        ch.viewers,
        streamUrl,
        ch.enabled ?? true,
        asString(ch.drm, 'none'),
        asString(ch.clearKeyKidKey, ''),
        normalizeChannelAudioLanguage(ch.audioLanguage),
      ],
    );
    return;
  }
  const maxSort = await pool.query(`SELECT COALESCE(MAX(sort_order), -1) AS m FROM channels`);
  const sortOrder = Number(maxSort.rows[0]?.m ?? -1) + 1;
  await pool.query(
    `INSERT INTO channels (id, name, cat, img, free, viewers, stream_url, enabled, drm, clear_key_kid_key, audio_language, sort_order)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
    [
      ch.id,
      ch.name,
      ch.cat,
      ch.img,
      ch.free,
      ch.viewers,
      streamUrl,
      ch.enabled ?? true,
      asString(ch.drm, 'none'),
      asString(ch.clearKeyKidKey, ''),
      normalizeChannelAudioLanguage(ch.audioLanguage),
      sortOrder,
    ],
  );
  await pool.query(
    `SELECT setval(pg_get_serial_sequence('channels','id'), (SELECT COALESCE(MAX(id),1) FROM channels))`,
  );
}

export async function deleteChannelFast(channelId: number): Promise<boolean> {
  if (!Number.isFinite(channelId)) {
    throw new HttpError(400, 'Invalid channel id', 'BAD_CHANNEL_ID');
  }
  const pool = requirePool();
  const out = await pool.query(`DELETE FROM channels WHERE id = $1`, [channelId]);
  return (out.rowCount ?? 0) > 0;
}

export async function reorderChannelsFast(ids: number[]): Promise<void> {
  if (!Array.isArray(ids) || ids.length === 0) {
    throw new HttpError(400, 'ids must be a non-empty array', 'BAD_REORDER');
  }
  const pool = requirePool();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (let i = 0; i < ids.length; i++) {
      const id = asInt(ids[i]);
      if (id === null) continue;
      await client.query(`UPDATE channels SET sort_order = $2 WHERE id = $1`, [id, i]);
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

export async function replaceCarouselFast(slides: unknown[]): Promise<void> {
  const pool = requirePool();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`DELETE FROM carousel_slides`);
    let sort = 0;
    for (const s of slides) {
      const x = (s ?? {}) as Record<string, unknown>;
      const channelId = asInt(x.channelId);
      if (channelId === null) continue;
      await client.query(
        `INSERT INTO carousel_slides (badge, badge_icon, title, channel_id, img, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [
          asString(x.badge, ''),
          asString(x.badgeIcon, ''),
          asString(x.title, ''),
          channelId,
          asString(x.img, ''),
          sort,
        ],
      );
      sort += 1;
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

export async function upsertMalipoPlanFast(body: unknown): Promise<void> {
  if (!body || typeof body !== 'object') {
    throw new HttpError(400, 'Invalid malipo plan body', 'BAD_MALIPO');
  }
  const x = body as Record<string, unknown>;
  const id = asString(x.id, '').trim();
  if (!id) {
    throw new HttpError(400, 'Malipo plan id is required', 'BAD_MALIPO_ID');
  }
  const pool = requirePool();
  const existing = await pool.query(`SELECT id FROM malipo_plans WHERE id = $1`, [id]);
  const values = [
    asString(x.label, ''),
    asString(x.priceLines, ''),
    asString(x.amount, ''),
    asString(x.period, ''),
    asBool(x.popular, false),
    accentRgbFromDartColor(x.accent1),
    accentRgbFromDartColor(x.accent2),
    asString(x.badge, ''),
  ];
  if (existing.rowCount && existing.rowCount > 0) {
    await pool.query(
      `UPDATE malipo_plans
       SET label = $2, price_lines = $3, amount = $4, period = $5, popular = $6,
           accent1 = $7, accent2 = $8, badge = $9
       WHERE id = $1`,
      [id, ...values],
    );
    return;
  }
  const maxSort = await pool.query(`SELECT COALESCE(MAX(sort_order), -1) AS m FROM malipo_plans`);
  const sortOrder = Number(maxSort.rows[0]?.m ?? -1) + 1;
  await pool.query(
    `INSERT INTO malipo_plans (id, label, price_lines, amount, period, popular, accent1, accent2, badge, sort_order)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
    [id, ...values, sortOrder],
  );
}

export async function deleteMalipoPlanFast(id: string): Promise<boolean> {
  const pool = requirePool();
  const out = await pool.query(`DELETE FROM malipo_plans WHERE id = $1`, [id.trim()]);
  return (out.rowCount ?? 0) > 0;
}

export async function upsertLiveMatchFast(body: unknown): Promise<void> {
  if (!body || typeof body !== 'object') {
    throw new HttpError(400, 'Invalid live match body', 'BAD_LIVE');
  }
  const x = body as Record<string, unknown>;
  const id = asInt(x.id);
  if (id === null) {
    throw new HttpError(400, 'Live match id must be a number', 'BAD_LIVE_ID');
  }
  const pool = requirePool();
  const channelId = asInt(x.channelId);
  const title = asString(x.title, '');
  const liveBadge = asBool(x.liveBadge, true);
  const matchTime = asString(x.matchTime, '');
  const existing = await pool.query(`SELECT id FROM live_matches WHERE id = $1`, [id]);
  if (existing.rowCount && existing.rowCount > 0) {
    await pool.query(
      `UPDATE live_matches
       SET title = $2, channel_id = $3, live_badge = $4, match_time = $5
       WHERE id = $1`,
      [id, title, channelId, liveBadge, matchTime],
    );
    return;
  }
  const maxSort = await pool.query(`SELECT COALESCE(MAX(sort_order), -1) AS m FROM live_matches`);
  const sortOrder = Number(maxSort.rows[0]?.m ?? -1) + 1;
  await pool.query(
    `INSERT INTO live_matches (id, title, sport, sport_icon, img, channel_id, live_badge, sort_order, match_time)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [id, title, '', '', '', channelId, liveBadge, sortOrder, matchTime],
  );
  await pool.query(
    `SELECT setval(pg_get_serial_sequence('live_matches','id'), (SELECT COALESCE(MAX(id),1) FROM live_matches))`,
  );
}

export async function deleteLiveMatchFast(id: number): Promise<boolean> {
  const pool = requirePool();
  const out = await pool.query(`DELETE FROM live_matches WHERE id = $1`, [id]);
  return (out.rowCount ?? 0) > 0;
}

export async function setCustomerCareWhatsappFast(raw: unknown): Promise<void> {
  const pool = requirePool();
  const digits = String(raw ?? '').replace(/\D/g, '');
  const value = digits.length >= 8 && digits.length <= 15 ? digits : '212600000000';
  await pool.query(
    `INSERT INTO app_settings (key, value) VALUES ('customerCareWhatsapp', $1)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [value],
  );
  await pool.query(
    `UPDATE app_settings SET value = (EXTRACT(EPOCH FROM now()) * 1000)::bigint::text
     WHERE key = 'configSyncedAt'`,
  );
}
