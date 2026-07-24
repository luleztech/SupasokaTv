/** True only for explicit per-number / STK attempt rate limits — not generic gateway codes. */
export function isPaymentRateLimitError(message: string, code: string): boolean {
  const msg = String(message || '').toLowerCase();
  const codeStr = String(code ?? '').trim();
  const combined = `${msg} ${codeStr}`.toLowerCase();

  // Explicit rate-limit language from Sonic / wallets (Swahili or English).
  if (
    combined.includes('too many') ||
    combined.includes('many attempt') ||
    combined.includes('rate limit') ||
    combined.includes('limit reached') ||
    combined.includes('majaribio mengi') ||
    /attempts?\s+(exceeded|limit)/i.test(combined) ||
    /exceeded\s+(the\s+)?(rate|request|attempt|limit)/i.test(combined)
  ) {
    return true;
  }

  // HTTP 429 alone is ambiguous (CDN/edge). Only treat as wallet rate-limit with attempt language.
  if (
    (codeStr === '429' || /\b429\b/.test(combined)) &&
    /request|attempt|limit|mara|majaribio|later/i.test(msg)
  ) {
    return true;
  }

  // Do NOT treat bare 9009/90009, "exceeded", or "try again later" as rate limit —
  // those are common on generic STK/push failures across all TZ networks.
  return false;
}

export function paymentRateLimitUserMessage(): string {
  return 'Umefanya majaribio mengi kwa nambari hii. Subiri dakika 2–5 bila kubonyeza tena, kisha jaribu.';
}

const STK_FAILURE_CODES = new Set([
  '9012', '999', '103', '9009', '90009', '500', '502', '503', '504', '408',
]);

/** Gateway accepted the HTTP call but USSD/STK was not delivered to the handset. */
export function isMobileMoneyStkSendFailure(rawMessage: string, rawCode: string): boolean {
  const msg = String(rawMessage || '').trim();
  const code = String(rawCode ?? '').trim();
  const combined = `${msg} ${code}`.toLowerCase();
  if (code && STK_FAILURE_CODES.has(code)) return true;
  if (/^general system error/i.test(msg)) return true;
  if (/\b9012\b|\b999\b|\b9009\b|\b90009\b/.test(combined)) return true;
  if (
    /\bambiguous\b|\bfail\b|\berror\b/.test(combined) &&
    /upstream|system|ussd|push|send|reponse|response/i.test(combined)
  ) {
    return true;
  }
  return (
    /hayajatumika|malipo hayajatumika|hayajaweza kutumika|malipo hayajaweza kutumika|hayajaweza kutuma/i.test(
      combined,
    ) ||
    /not sent|could not send|push failed|failed to send|unable to send|cannot send|was not sent/i.test(
      combined,
    ) ||
    /no reponse from upstream|no response from upstream|upstream system|upstream/i.test(combined) ||
    /rejecting.*ussd|ongoing ussd|ussd session/i.test(combined)
  );
}

/** Clear invalid-phone / MSISDN format errors — safe to retry once with alternate format. */
export function isInvalidPhonePaymentError(message: string, code: string): boolean {
  const combined = `${message} ${code}`.toLowerCase();
  return /invalid phone|invalid msisdn|wrong number|invalid.*msisdn|nambari.*si sahihi|unsupported.*phone|phone.*format/i.test(
    combined,
  );
}

/**
 * Safe to try another phone format. STK delivery failures are NOT recoverable via
 * extra gateway hits — those burn Sonic's per-MSISDN quota and surface as Subiri 2–5.
 */
export function isRecoverablePaymentCreateError(message: string, code: string): boolean {
  if (isPaymentRateLimitError(message, code)) return false;
  if (isMobileMoneyStkSendFailure(message, code)) return false;
  return isInvalidPhonePaymentError(message, code);
}

/** Only retry create when another phone format might help (not STK / rate-limit). */
export function isPaymentCreateRetryable(message: string, code: string): boolean {
  if (isPaymentRateLimitError(message, code)) return false;
  return isInvalidPhonePaymentError(message, code);
}
