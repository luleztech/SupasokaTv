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

/** Safe to try another phone format or wallet provider (not a rate limit). */
export function isRecoverablePaymentCreateError(message: string, code: string): boolean {
  if (isPaymentRateLimitError(message, code)) return false;
  const combined = `${message} ${code}`.toLowerCase();
  return (
    /invalid phone|invalid msisdn|wrong number|nambari|not registered|subscriber|wallet|provider|network|format|unsupported|unknown operator/i.test(
      combined,
    ) ||
    /hayajatumika|malipo hayajatumika|hayajaweza kutumika|not sent|could not send|push failed|failed to send/i.test(
      combined,
    ) ||
    /no response from upstream|upstream system|ongoing ussd/i.test(combined)
  );
}
