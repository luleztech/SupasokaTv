import { toLocal0Digits } from '../lib/tzPhone';

/** Minimum gap between SonicPesa create_order calls for the same MSISDN. */
const COOLDOWN_MS = 75_000;

const recentByPhone = new Map<string, number>();

function pruneStale(): void {
  if (recentByPhone.size < 4000) return;
  const cutoff = Date.now() - COOLDOWN_MS * 2;
  for (const [phone, at] of recentByPhone) {
    if (at < cutoff) recentByPhone.delete(phone);
  }
}

/**
 * Returns a Swahili user message when the same phone was used for checkout too recently.
 * Prevents hammering SonicPesa (which surfaces as "Too Many Attempts" on every tap).
 */
export function paymentStartCooldownMessage(localPhone: string): string | null {
  const key = toLocal0Digits(localPhone);
  const last = recentByPhone.get(key);
  if (!last) return null;
  const elapsed = Date.now() - last;
  if (elapsed >= COOLDOWN_MS) {
    recentByPhone.delete(key);
    return null;
  }
  const waitSec = Math.max(1, Math.ceil((COOLDOWN_MS - elapsed) / 1000));
  return (
    `Ombi la malipo limetumwa hivi karibuni kwa nambari hii. ` +
    `Subiri sekunde ${waitSec} bila kubonyeza "Lipia sasa" tena, kisha angalia simu yako kwa PIN.`
  );
}

/** Call immediately before the first SonicPesa create_order for this checkout. */
export function markPaymentStartAttempt(localPhone: string): void {
  recentByPhone.set(toLocal0Digits(localPhone), Date.now());
  pruneStale();
}
