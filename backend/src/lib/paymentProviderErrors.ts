/** M-Pesa / wallet STK rate-limit and "too many attempts" responses. */
export function isPaymentRateLimitError(message: string, code: string): boolean {
  const combined = `${message} ${code}`.toLowerCase();
  return (
    combined.includes('too many') ||
    combined.includes('many attempt') ||
    combined.includes('exceeded') ||
    combined.includes('rate limit') ||
    combined.includes('try again later') ||
    combined.includes('limit reached') ||
    code === '429' ||
    /\b(9009|90009)\b/.test(combined)
  );
}

export function paymentRateLimitUserMessage(): string {
  return 'Umefanya majaribio mengi kwa nambari hii. Subiri dakika 2–5 bila kubonyeza tena, kisha jaribu.';
}

const STK_FAILURE_CODES = new Set([
  '9012', '999', '103', '9009', '90009', '500', '502', '503', '504', '408', '429',
]);

/** Gateway accepted the HTTP call but USSD/STK was not delivered to the handset. */
export function isMobileMoneyStkSendFailure(rawMessage: string, rawCode: string): boolean {
  const msg = String(rawMessage || '').trim();
  const code = String(rawCode ?? '').trim();
  const combined = `${msg} ${code}`.toLowerCase();
  if (code && STK_FAILURE_CODES.has(code)) return true;
  if (/^general system error/i.test(msg)) return true;
  if (/\b9012\b|\b999\b/.test(combined)) return true;
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

/** Safe to try another phone format or wallet provider (not a rate limit). */
export function isRecoverablePaymentCreateError(message: string, code: string): boolean {
  if (isPaymentRateLimitError(message, code)) return false;
  if (isMobileMoneyStkSendFailure(message, code)) return true;
  const combined = `${message} ${code}`.toLowerCase();
  return (
    /invalid phone|invalid msisdn|wrong number|nambari si sahihi|not registered|subscriber|wallet|provider|network|format|unsupported|unknown operator/i.test(
      combined,
    ) ||
    /hayajatumika|malipo hayajatumika|hayajaweza kutumika|not sent|could not send|push failed|failed to send/i.test(
      combined,
    ) ||
    /no response from upstream|upstream system|ongoing ussd/i.test(combined)
  );
}

export function isPaymentCreateRetryable(message: string, code: string): boolean {
  if (isPaymentRateLimitError(message, code)) return false;
  return isRecoverablePaymentCreateError(message, code) || isMobileMoneyStkSendFailure(message, code);
}
