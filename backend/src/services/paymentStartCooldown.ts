import { toLocal0Digits } from '../lib/tzPhone';

/** Minimum gap between successful STK dispatches for the same MSISDN. */
const COOLDOWN_MS = 60_000;

/** After this long with a still-pending order, allow a clean retry (silent STK). */
const PENDING_RETRY_MS = 45_000;

type CooldownEntry = {
  at: number;
  orderId?: string;
  provider?: string;
};

const lastSuccessfulSendByPhone = new Map<string, CooldownEntry>();

function pruneStale(): void {
  if (lastSuccessfulSendByPhone.size < 4000) return;
  const cutoff = Date.now() - COOLDOWN_MS * 5;
  for (const [phone, entry] of lastSuccessfulSendByPhone) {
    if (entry.at < cutoff) lastSuccessfulSendByPhone.delete(phone);
  }
}

export function getPaymentStartCooldownEntry(
  localPhone: string,
): { at: number; orderId?: string; provider?: string } | null {
  const key = toLocal0Digits(localPhone);
  const entry = lastSuccessfulSendByPhone.get(key);
  if (!entry) return null;
  if (Date.now() - entry.at >= COOLDOWN_MS) {
    // Keep a soft record a bit longer so we can skip a dead Aurax prefer on retry.
    return null;
  }
  return entry;
}

/** Soft history (past hard cooldown) — used to break silent-STK Aurax loops. */
export function getRecentPaymentStartEntry(
  localPhone: string,
): { at: number; orderId?: string; provider?: string } | null {
  const key = toLocal0Digits(localPhone);
  const entry = lastSuccessfulSendByPhone.get(key);
  if (!entry) return null;
  if (Date.now() - entry.at >= COOLDOWN_MS * 5) {
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

/** True when a prior "success" is old enough that a silent STK miss is likely. */
export function isPaymentStartPendingRetryWindow(localPhone: string): boolean {
  const entry = getRecentPaymentStartEntry(localPhone);
  if (!entry) return false;
  return Date.now() - entry.at >= PENDING_RETRY_MS;
}

/** Call only after a gateway accepts the order and STK was dispatched. */
export function markPaymentStartSent(
  localPhone: string,
  orderId?: string,
  provider?: string,
): void {
  const key = toLocal0Digits(localPhone);
  const trimmedOrder = String(orderId ?? '').trim();
  const trimmedProvider = String(provider ?? '').trim().toLowerCase();
  lastSuccessfulSendByPhone.set(key, {
    at: Date.now(),
    ...(trimmedOrder ? { orderId: trimmedOrder } : {}),
    ...(trimmedProvider ? { provider: trimmedProvider } : {}),
  });
  pruneStale();
}
