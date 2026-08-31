import { toLocal0Digits } from '../lib/tzPhone';

/** Minimum gap between successful STK dispatches for the same MSISDN. */
const COOLDOWN_MS = 60_000;

type CooldownEntry = { at: number; orderId?: string };

const lastSuccessfulSendByPhone = new Map<string, CooldownEntry>();

function pruneStale(): void {
  if (lastSuccessfulSendByPhone.size < 4000) return;
  const cutoff = Date.now() - COOLDOWN_MS * 2;
  for (const [phone, entry] of lastSuccessfulSendByPhone) {
    if (entry.at < cutoff) lastSuccessfulSendByPhone.delete(phone);
  }
}

export function getPaymentStartCooldownEntry(
  localPhone: string,
): { at: number; orderId?: string } | null {
  const key = toLocal0Digits(localPhone);
  const entry = lastSuccessfulSendByPhone.get(key);
  if (!entry) return null;
  if (Date.now() - entry.at >= COOLDOWN_MS) {
    lastSuccessfulSendByPhone.delete(key);
    return null;
  }
  return entry;
}

/** Drop in-memory cooldown for a phone (e.g. prior order failed or user is retrying cleanly). */
export function clearPaymentStartCooldown(localPhone: string): void {
  lastSuccessfulSendByPhone.delete(toLocal0Digits(localPhone));
}

/**
 * Returns a Swahili user message when STK was already sent to this phone very recently.
 * Only blocks after a **successful** dispatch — failed attempts can retry immediately.
 */
export function paymentStartCooldownMessage(localPhone: string): string | null {
  const entry = getPaymentStartCooldownEntry(localPhone);
  if (!entry) return null;
  const elapsed = Date.now() - entry.at;
  const waitSec = Math.max(1, Math.ceil((COOLDOWN_MS - elapsed) / 1000));
  return (
    `Ombi la malipo limetumwa kwenye simu yako. ` +
    `Angalia PIN kwenye simu. Usibofye "Lipia sasa" tena kwa sekunde ${waitSec}.`
  );
}

/** Call only after SonicPesa accepts the order and STK was dispatched. */
export function markPaymentStartSent(localPhone: string, orderId?: string): void {
  const key = toLocal0Digits(localPhone);
  const trimmedOrder = String(orderId ?? '').trim();
  lastSuccessfulSendByPhone.set(key, {
    at: Date.now(),
    ...(trimmedOrder ? { orderId: trimmedOrder } : {}),
  });
  pruneStale();
}
