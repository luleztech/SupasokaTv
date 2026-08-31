/**
 * True only for explicit per-MSISDN / wallet attempt quotas.
 * Never treat Railway/CDN "Too Many Requests", bare 429, 9009, or "try again later"
 * as "umefanya majaribio mengi kwa nambari hii" — that falsely blocks first-time 070/Yas users.
 */
export function isPaymentRateLimitError(message: string, code: string): boolean {
  const msg = String(message || '').toLowerCase().trim();
  const codeStr = String(code ?? '').trim();
  const combined = `${msg} ${codeStr}`.toLowerCase();

  // Our own / known Swahili per-number copy.
  if (
    combined.includes('majaribio mengi') ||
    combined.includes('umefanya majaribio') ||
    /subiri dakika\s*2|subiri dakika\s*5|dakika 2–5|dakika 2-5/i.test(combined)
  ) {
    return true;
  }

  // Sonic per-MSISDN / merchant quota (often after chained create_order calls).
  if (/too many attempts?/i.test(msg)) {
    return true;
  }

  // Generic edge/CDN throttling — NOT a phone-number quota.
  if (
    /^too many requests$/i.test(msg) ||
    /^rate limited$/i.test(msg) ||
    /railway|edge rate|api rate limit|global rate/i.test(combined)
  ) {
    return false;
  }

  const mentionsNumber =
    /nambari|number|phone|msisdn|simu|buyer[_\s]?phone|this (number|phone|msisdn)/i.test(
      combined,
    );
  const mentionsAttempts =
    /majaribio|attempt|tries|jaribio|too many (payment )?attempt|many attempt/i.test(
      combined,
    );

  // Must tie the quota to the phone / MSISDN.
  if (mentionsNumber && mentionsAttempts) return true;
  if (
    mentionsNumber &&
    /(rate\s*limit|limit reached|exceeded.*(?:attempt|limit)|attempt.*exceeded)/i.test(
      combined,
    )
  ) {
    return true;
  }
  if (
    /(number|phone|msisdn|nambari).{0,40}(too many|rate\s*limit|limit reached|exceeded)/i.test(
      combined,
    )
  ) {
    return true;
  }
  if (
    /(too many|rate\s*limit|limit reached|exceeded).{0,40}(number|phone|msisdn|nambari)/i.test(
      combined,
    )
  ) {
    return true;
  }

  // Bare HTTP 429 / "too many" / "rate limit" without phone context = not per-number.
  return false;
}

export function paymentRateLimitUserMessage(): string {
  return 'Umefanya majaribio mengi kwa nambari hii. Subiri dakika 2–5 bila kubonyeza tena, kisha jaribu.';
}

/** Soft busy message for CDN/API throttling (not the user's phone). */
export function paymentBusyUserMessage(): string {
  return 'Huduma ina shughuli nyingi sasa. Subiri sekunde chache, kisha jaribu tena.';
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

/** Wrong/unknown wallet channel — safe to retry with auto-detect or another channel hint. */
export function isWalletRoutingPaymentError(message: string, code: string): boolean {
  const combined = `${message} ${code}`.toLowerCase();
  return (
    /unknown (channel|network|operator|provider|wallet)/i.test(combined) ||
    /invalid (channel|network|operator|provider|wallet)/i.test(combined) ||
    /unsupported (channel|network|operator|provider|wallet)/i.test(combined) ||
    /could not (detect|determine|resolve).*(channel|network|operator|wallet)/i.test(combined) ||
    /unable to (detect|determine|resolve).*(channel|network|operator|wallet)/i.test(combined) ||
    /wallet.*(not supported|unsupported|unknown)/i.test(combined)
  );
}

/**
 * Safe to try another phone format or channel. STK delivery failures are NOT recoverable via
 * extra gateway hits — those burn Sonic's per-MSISDN quota and surface as Subiri 2–5.
 */
export function isRecoverablePaymentCreateError(message: string, code: string): boolean {
  if (isPaymentRateLimitError(message, code)) return false;
  if (isMobileMoneyStkSendFailure(message, code)) return false;
  return isInvalidPhonePaymentError(message, code) || isWalletRoutingPaymentError(message, code);
}

/** Only retry create when another phone format / channel might help (not STK / rate-limit). */
export function isPaymentCreateRetryable(message: string, code: string): boolean {
  return isRecoverablePaymentCreateError(message, code);
}
