export function asString(raw: unknown, fallback = ''): string {
  if (raw === null || raw === undefined) return fallback;
  return String(raw);
}

export function asInt(raw: unknown): number | null {
  const n = Number(raw);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

export function asBool(raw: unknown, fallback: boolean): boolean {
  if (raw === true || raw === false) return raw;
  const s = String(raw ?? '').trim().toLowerCase();
  if (s === 'false' || s === '0' || s === 'no') return false;
  if (s === 'true' || s === '1' || s === 'yes') return true;
  return fallback;
}

/** ISO 639-1 audio preference for playback: `sw` (default) | `en`. */
export function normalizeChannelAudioLanguage(raw: unknown): string {
  const r = String(raw ?? '').trim().toLowerCase();
  if (r === 'en' || r.startsWith('en-') || r === 'english' || r === 'eng') return 'en';
  if (r === 'sw' || r.startsWith('sw-') || r === 'swahili' || r === 'kiswahili' || r === 'swa') return 'sw';
  return 'sw';
}

/** Dart `Color.value` is 32-bit ARGB (>2^31-1); PG INTEGER must stay ≤ 2147483647. Keep RGB only. */
export function accentRgbFromDartColor(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) return 0;
  const u = Math.trunc(n) >>> 0;
  return u & 0xffffff;
}

export function digitsWhatsapp(raw: unknown): string {
  const s = String(raw ?? '').replace(/\D/g, '');
  if (s.length >= 8 && s.length <= 15) return s;
  return '212600000000';
}
