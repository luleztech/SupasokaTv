/** Latest admin grant in the note. A newer save wins over an older one. */
export function adminGrantMs(note: string | null | undefined): number {
  const text = String(note ?? '');
  let best = 0;
  for (const match of text.matchAll(/premium_admin_grant:(\d{10,})/g)) {
    const n = Number(match[1]);
    if (Number.isFinite(n) && n > best) best = n;
  }
  return best;
}

export function noteWithAdminGrant(note: string | null | undefined, grantMs: number): string {
  const stripped = String(note ?? '')
    .replace(/(\s*\|\s*)?premium_revoked:(admin|no_verified_payment)/gi, '')
    .replace(/(\s*\|\s*)?premium_admin_grant:\d+/gi, '')
    .replace(/\s*\|\s*/g, ' | ')
    .replace(/^\s*\|\s*|\s*\|\s*$/g, '')
    .trim();
  const marker = `premium_admin_grant:${Math.trunc(grantMs)}`;
  return stripped ? `${stripped} | ${marker}` : marker;
}

export function noteWithoutAdminGrant(note: string | null | undefined): string {
  let text = String(note ?? '')
    .replace(/(\s*\|\s*)?premium_admin_grant:\d+/gi, '')
    .replace(/\s*\|\s*/g, ' | ')
    .replace(/^\s*\|\s*|\s*\|\s*$/g, '')
    .trim();
  if (!text.includes('premium_revoked:')) {
    text = text ? `${text} | premium_revoked:admin` : 'premium_revoked:admin';
  }
  return text;
}
