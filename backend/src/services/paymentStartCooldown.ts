import { toLocal0Digits } from '../lib/tzPhone';

/** Minimum gap between successful STK dispatches for the same MSISDN. */
const COOLDOWN_MS = 60_000;

const lastSuccessfulSendByPhone = new Map<string, number>();

function pruneStale(): void {
  if (lastSuccessfulSendByPhone.size < 4000) return;
  const cutoff = Date.now() - COOLDOWN_MS * 2;
  for (const [phone, at] of lastSuccessfulSendByPhone) {
    if (at < cutoff) lastSuccessfulSendByPhone.delete(phone);
  }
}

/**
 * Returns a Swahili user message when STK was already sent to this phone very recently.
 * Only blocks after a **successful** dispatch — failed attempts can retry immediately.
 */
export function paymentStartCooldownMessage(localPhone: string): string | null {
  const key = toLocal0Digits(localPhone);
  const last = lastSuccessfulSendByPhone.get(key);
  if (!last) return null;
  const elapsed = Date.now() - last;
  if (elapsed >= COOLDOWN_MS) {
    lastSuccessfulSendByPhone.delete(key);
    return null;
  }
  const waitSec = Math.max(1, Math.ceil((COOLDOWN_MS - elapsed) / 1000));
  return (
    `Ombi la malipo limetumwa kwenye simu yako. ` +
    `Angalia PIN kwenye simu. Usibofye "Lipia sasa" tena kwa sekunde ${waitSec}.`
  );
}

/** Call only after SonicPesa accepts the order and STK was dispatched. */
export function markPaymentStartSent(localPhone: string): void {
  lastSuccessfulSendByPhone.set(toLocal0Digits(localPhone), Date.now());
  pruneStale();
}
