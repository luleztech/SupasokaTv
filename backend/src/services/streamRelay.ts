import type { Request, Response } from 'express';
import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import { isTokenizedCdnUrl, playbackHeadersForStreamUrl } from '../lib/cdnTokenHeaders';

const RELAY_TIMEOUT_MS = 25_000;

function normalizeUpstreamUrl(raw: string): string {
  const u = String(raw ?? '').trim();
  if (!u) throw new HttpError(404, 'Channel stream URL is not configured', 'NO_STREAM_URL');
  return u;
}

async function loadChannelStreamUrl(channelId: number): Promise<string> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured on the API service', 'NO_DATABASE');
  }
  const res = await pool.query<{ stream_url: string; enabled: boolean }>(
    `SELECT stream_url, enabled FROM channels WHERE id = $1`,
    [channelId],
  );
  const row = res.rows[0];
  if (!row?.enabled) {
    throw new HttpError(404, 'Channel not found or disabled', 'CHANNEL_NOT_FOUND');
  }
  return normalizeUpstreamUrl(row.stream_url);
}

function upstreamBaseForManifest(upstream: string): string {
  const idx = upstream.lastIndexOf('/');
  return idx > 0 ? upstream.slice(0, idx + 1) : `${upstream}/`;
}

function resolveRelayTarget(upstream: string, suffix: string): string {
  const clean = suffix.replace(/^\/+/, '');
  if (!clean || clean === 'manifest' || clean === 'master.mpd') {
    return upstream;
  }
  const base = upstreamBaseForManifest(upstream);
  try {
    return new URL(clean, base).toString();
  } catch {
    return `${base}${clean}`;
  }
}

function rewriteMpdForRelay(mpd: string, relayBase: string): string {
  const base = relayBase.endsWith('/') ? relayBase : `${relayBase}/`;
  return mpd.replace(
    /((?:initialization|media|sourceURL)=")(?!https?:\/\/)([^"]+)"/gi,
    (_m, prefix: string, rel: string) => `${prefix}${base}${rel.replace(/^\//, '')}"`,
  );
}

export function relayPlaybackUrl(apiOrigin: string, channelId: number, upstream: string): string | null {
  if (!isTokenizedCdnUrl(upstream)) return null;
  const origin = apiOrigin.replace(/\/$/, '');
  return `${origin}/api/v1/public/relay/${channelId}/manifest`;
}

export async function proxyRelayRequest(
  channelId: number,
  suffix: string,
  req: Request,
  res: Response,
): Promise<void> {
  const upstream = await loadChannelStreamUrl(channelId);
  const target = resolveRelayTarget(upstream, suffix);
  const headers = playbackHeadersForStreamUrl(upstream);
  const range = req.header('range');
  if (range) headers.Range = range;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), RELAY_TIMEOUT_MS);
  try {
    const upstreamRes = await fetch(target, {
      method: 'GET',
      headers,
      signal: controller.signal,
      redirect: 'follow',
    });

    res.status(upstreamRes.status);
    const contentType = upstreamRes.headers.get('content-type');
    if (contentType) res.setHeader('Content-Type', contentType);
    const contentLength = upstreamRes.headers.get('content-length');
    if (contentLength) res.setHeader('Content-Length', contentLength);
    const acceptRanges = upstreamRes.headers.get('accept-ranges');
    if (acceptRanges) res.setHeader('Accept-Ranges', acceptRanges);
    const contentRange = upstreamRes.headers.get('content-range');
    if (contentRange) res.setHeader('Content-Range', contentRange);
    res.setHeader('Cache-Control', 'no-store');

    if (!upstreamRes.ok) {
      const errBody = await upstreamRes.text();
      res.send(errBody);
      return;
    }

    const isMpd =
      target.toLowerCase().includes('.mpd') ||
      suffix === 'manifest' ||
      suffix === 'master.mpd' ||
      (contentType?.includes('dash+xml') ?? false);

    if (isMpd) {
      const mpd = await upstreamRes.text();
      const relayBase = `${req.protocol}://${req.get('host')}/api/v1/public/relay/${channelId}/`;
      res.send(rewriteMpdForRelay(mpd, relayBase));
      return;
    }

    const buf = Buffer.from(await upstreamRes.arrayBuffer());
    res.send(buf);
  } finally {
    clearTimeout(timer);
  }
}
