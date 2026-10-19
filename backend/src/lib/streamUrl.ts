/**
 * One canonical stream URL for storage, admin, and playback.
 * Pasted links often contain newlines, wrapping quotes, or invisible
 * characters. Those still look like a link in a text field, but players
 * treat them as missing or refuse to open them until the link is retyped.
 */
const URL_NOISE =
  /[\s\u00A0\u1680\u180E\u2000-\u200F\u2028-\u202F\u205F-\u2064\u2066-\u2069\uFEFF\u3000]/g;

function unwrapOnce(value: string): string {
  const pairs: Array<[string, string]> = [
    ['"', '"'],
    ["'", "'"],
    ['`', '`'],
    ['“', '”'],
    ['‘', '’'],
    ['<', '>'],
  ];
  for (const [open, close] of pairs) {
    if (value.length >= open.length + close.length && value.startsWith(open) && value.endsWith(close)) {
      return value.slice(open.length, value.length - close.length);
    }
  }
  return value;
}

export function normalizeStreamUrl(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  let s = unwrapOnce(raw.trim());
  s = unwrapOnce(s).replace(URL_NOISE, '');
  const at = s.search(/https?:\/\//i);
  if (at > 0) s = s.slice(at);
  return s;
}

/** First alias that is a real link. Empty string must not hide a later alias. */
export function firstStreamUrl(values: unknown[]): string {
  for (const value of values) {
    const url = normalizeStreamUrl(value);
    if (url) return url;
  }
  return '';
}

/**
 * What to write into `channels.stream_url`.
 * A real incoming link wins. An omitted/blank link keeps the saved one.
 * `clearRequested` is the only way a blank value deletes the saved link.
 */
export function resolveStoredStreamUrl(
  incoming: unknown[],
  existing: unknown,
  clearRequested: boolean,
): string {
  const next = firstStreamUrl(incoming);
  if (next) return next;
  if (clearRequested) return '';
  return normalizeStreamUrl(existing);
}

/** Channel id 0 is valid. Only missing or negative ids are rejected. */
export function isPlayableChannelId(id: number): boolean {
  return Number.isInteger(id) && id >= 0;
}
