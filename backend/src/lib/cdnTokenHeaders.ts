const TOK_PATTERN = /\/tok_([^.]+)\.([^.]+)\.([^/]+)\//;

function decodeBase64Url(segment: string): string | null {
  try {
    const normalized = segment.replace(/-/g, '+').replace(/_/g, '/');
    const pad = normalized.length % 4 === 0 ? '' : '='.repeat(4 - (normalized.length % 4));
    return Buffer.from(normalized + pad, 'base64').toString('utf8');
  } catch {
    return null;
  }
}

/** JWT `url` field required as Referer/Origin for Azam/Nagra `tok_` CDN URLs. */
export function cdnTokenRefererOrigin(rawUrl: string): { referer: string; origin: string } | null {
  const match = TOK_PATTERN.exec(String(rawUrl ?? '').trim());
  if (!match?.[2]) return null;
  const jsonText = decodeBase64Url(match[2]);
  if (!jsonText) return null;
  try {
    const payload = JSON.parse(jsonText) as Record<string, unknown>;
    const allowed = String(payload.url ?? payload.referer ?? payload.origin ?? '').trim();
    if (!allowed) return null;
    const parsed = new URL(allowed);
    const port =
      parsed.port && parsed.port !== '80' && parsed.port !== '443' ? `:${parsed.port}` : '';
    const origin = `${parsed.protocol}//${parsed.hostname}${port}`;
    const referer = origin.endsWith('/') ? origin : `${origin}/`;
    return { referer, origin };
  } catch {
    return null;
  }
}

export function isTokenizedCdnUrl(rawUrl: string): boolean {
  return TOK_PATTERN.test(String(rawUrl ?? '').trim());
}

export type ChannelRequestHeaders = {
  referer?: string | null;
  origin?: string | null;
  userAgent?: string | null;
};

/** Admin Referer / Origin / User-Agent override the URL-derived defaults when set. */
export function withChannelRequestHeaders(
  base: Record<string, string>,
  custom: ChannelRequestHeaders,
): Record<string, string> {
  const headers = { ...base };
  const referer = String(custom.referer ?? '').trim();
  const origin = String(custom.origin ?? '').trim();
  const userAgent = String(custom.userAgent ?? '').trim();
  if (referer) headers.Referer = referer;
  if (origin) headers.Origin = origin;
  if (userAgent) headers['User-Agent'] = userAgent;
  return headers;
}

const CHROME_MOBILE_UA =
  'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

const IPTV_PORT_PATH = /^https?:\/\/[^/]+:\d{2,5}\/(live|stream|play|hls|iptv|channel|ch)\//i;
const IPTV_PORT_TRIPLE = /^https?:\/\/[^/]+:\d{2,5}\/[^/]+\/[^/]+\/[^/?#]+$/i;
const IPTV_HOST_PATH = /^https?:\/\/[^/]+\/(live|stream|play|hls|iptv|channel|ch)\/[^/?#]+/i;

function isDocumentPath(pathname: string): boolean {
  const path = pathname.toLowerCase();
  return (
    path.endsWith('.html') ||
    path.endsWith('.htm') ||
    path.endsWith('.asp') ||
    path.endsWith('.aspx') ||
    path.endsWith('.cgi') ||
    path.endsWith('.jsp')
  );
}

/** Direct playlists/files and plain HTTP streams. Page headers make these servers return 403. */
export function isDirectMediaUrl(rawUrl: string): boolean {
  const u = String(rawUrl ?? '').trim();
  if (!u) return false;
  if (u.toLowerCase().includes('.php')) return false;
  if (isTokenizedCdnUrl(u)) return false;
  let parsed: URL;
  try {
    parsed = new URL(u);
  } catch {
    return false;
  }
  const path = parsed.pathname.toLowerCase();
  if (
    path.endsWith('.m3u8') ||
    path.endsWith('.m3u') ||
    path.endsWith('.mpd') ||
    path.endsWith('.mp4') ||
    path.endsWith('.m4v') ||
    path.endsWith('.ts') ||
    path.endsWith('.mkv') ||
    path.endsWith('.webm')
  ) {
    return true;
  }
  const base = u.split('#')[0] ?? u;
  if (IPTV_PORT_PATH.test(base) || IPTV_PORT_TRIPLE.test(base) || IPTV_HOST_PATH.test(base)) {
    return true;
  }
  if (parsed.protocol === 'http:' && !isDocumentPath(path)) return true;
  return false;
}

export function playbackHeadersForStreamUrl(rawUrl: string): Record<string, string> {
  const u = String(rawUrl ?? '').trim();
  if (!u) return {};
  let parsed: URL;
  try {
    parsed = new URL(u);
  } catch {
    return {};
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return {};

  if (isDirectMediaUrl(u)) {
    const headers: Record<string, string> = {
      'User-Agent': CHROME_MOBILE_UA,
      Accept: '*/*',
      'Accept-Language': 'en-US,en;q=0.9,sw;q=0.8',
      Connection: 'keep-alive',
    };
    // Plain HTTP bridges reject the playlist unless the request names this app.
    if (parsed.protocol === 'http:') {
      headers['X-Requested-With'] = 'com.ayubu.supasoka';
    }
    return headers;
  }

  const origin = `${parsed.protocol}//${parsed.host}`;
  const token = cdnTokenRefererOrigin(u);
  const referer = token?.referer ?? `${origin}/`;
  const originHeader = token?.origin ?? origin;
  const headers: Record<string, string> = {
    Referer: referer,
    Origin: originHeader,
    'User-Agent': CHROME_MOBILE_UA,
    Connection: 'keep-alive',
    'Accept-Language': 'en-US,en;q=0.9,sw;q=0.8',
    Accept:
      'text/html,application/xhtml+xml,application/xml;q=0.9,application/dash+xml,application/vnd.apple.mpegurl;q=0.8,*/*;q=0.7',
  };
  if (u.toLowerCase().includes('.php')) {
    headers['X-Requested-With'] = 'com.ayubu.supasoka';
  }
  return headers;
}
