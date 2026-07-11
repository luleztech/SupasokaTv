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

export function playbackHeadersForStreamUrl(rawUrl: string): Record<string, string> {
  const u = String(rawUrl ?? '').trim();
  if (!u) return {};
  let origin = '';
  try {
    const parsed = new URL(u);
    origin = `${parsed.protocol}//${parsed.host}`;
  } catch {
    return {};
  }
  const token = cdnTokenRefererOrigin(u);
  const referer = token?.referer ?? `${origin}/`;
  const originHeader = token?.origin ?? origin;
  return {
    Referer: referer,
    Origin: originHeader,
    'User-Agent':
      'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    Connection: 'keep-alive',
    'Accept-Language': 'en-US,en;q=0.9,sw;q=0.8',
    Accept:
      'text/html,application/xhtml+xml,application/xml;q=0.9,application/dash+xml,application/vnd.apple.mpegurl;q=0.8,*/*;q=0.7',
  };
}
