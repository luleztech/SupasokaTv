/**
 * Tanzania mobile MSISDN (national format `0XXXXXXXXX`, 10 digits).
 * Accepts all standard TZ mobile NDC blocks: 061–069 and 070–079.
 */
export const TZ_MOBILE_PREFIXES = [
  '061', '062', '063', // Halotel / Viettel / Amotel
  '064', // CooTel (Wiafrica)
  '065', '067', '070', '071', '077', // Yas / tiGo (MIC)
  '066', // Smile
  '068', '069', '078', // Airtel
  '072', // MO Mobile Holding
  '073', // TTCL
  '074', '075', '076', '079', // Vodacom
] as const;

/** All assigned TZ mobile local numbers: 061–069 and 070–079 (10 digits). */
export const TZ_MOBILE_LOCAL_RE = /^0(6[1-9]|7[0-9])\d{7}$/;

export type TzMobileNetwork =
  | 'halotel'
  | 'cootel'
  | 'tigo_yas'
  | 'smile'
  | 'airtel'
  | 'mo_mobile'
  | 'ttcl'
  | 'vodacom'
  | 'unknown';

export type NormalizePhoneResult = { local?: string; error?: string };

export function isValidTzMobileLocal0(local0: string): boolean {
  const s = toLocal0Digits(local0);
  return TZ_MOBILE_LOCAL_RE.test(s);
}

/** Normalize any TZ MSISDN shape to national `0XXXXXXXXX` for routing (best effort). */
export function toLocal0Digits(raw: string): string {
  let s = String(raw ?? '').replace(/\D/g, '');
  if (s.startsWith('255') && s.length >= 12) {
    return `0${s.slice(3, 12)}`;
  }
  if (s.startsWith('255') && s.length > 9) {
    return `0${s.slice(3)}`.slice(0, 10);
  }
  if (s.length === 9 && /^[1-9]/.test(s)) {
    s = `0${s}`;
  }
  if (s.startsWith('0')) return s.slice(0, 10);
  return s.slice(0, 10);
}

export function detectTzMobileNetwork(local0: string): TzMobileNetwork {
  const p = toLocal0Digits(local0);
  if (/^06[123]/.test(p)) return 'halotel';
  if (p.startsWith('064')) return 'cootel';
  if (['065', '067', '070', '071', '077'].some((pre) => p.startsWith(pre))) return 'tigo_yas';
  if (p.startsWith('066')) return 'smile';
  if (/^06[89]/.test(p) || p.startsWith('078')) return 'airtel';
  if (p.startsWith('072')) return 'mo_mobile';
  if (p.startsWith('073')) return 'ttcl';
  if (/^07[45679]/.test(p) && !p.startsWith('078')) return 'vodacom';
  if (isValidTzMobileLocal0(p)) return 'unknown';
  return 'unknown';
}

export function normalizePhoneToLocal0(rawPhone: string): NormalizePhoneResult {
  let s = String(rawPhone ?? '').trim().replace(/\s+/g, '');
  if (!s) {
    return { error: 'Nambari ya simu inahitajika.' };
  }

  if (s.startsWith('+') && !s.toUpperCase().startsWith('+255')) {
    return {
      error:
        'Malipo yanatumwa kwa nambari za simu za Tanzania pekee. Tumia muundo wa ndani unaoanza na 0 (mfano 0712345678).',
    };
  }
  if (s.startsWith('00') && !s.toUpperCase().startsWith('00255')) {
    return {
      error:
        'Malipo yanatumwa kwa nambari za simu za Tanzania pekee. Tumia muundo wa ndani unaoanza na 0 (mfano 0712345678).',
    };
  }

  if (s.toUpperCase().startsWith('+255')) {
    s = `0${s.slice(4)}`;
  } else if (s.toUpperCase().startsWith('00255')) {
    s = `0${s.slice(5)}`;
  } else if (/^255\d{9,}$/.test(s.replace(/\D/g, ''))) {
    const digits = s.replace(/\D/g, '');
    s = `0${digits.slice(3, 12)}`;
  }

  s = s.replace(/\D/g, '');

  if (/^[1-9]\d{8}$/.test(s)) {
    s = `0${s}`;
  }

  if (!/^0[1-9]\d{8}$/.test(s)) {
    return {
      error:
        'Nambari ya simu lazima iwe nambari 10 za Tanzania: anza kwa 0 kisha tarakimu 9 (mfano 0612345678 au 0751234567).',
    };
  }

  if (!isValidTzMobileLocal0(s)) {
    return {
      error:
        'Nambari hii si ya simu ya Tanzania. Tumia nambari halali ya ndani (061–069, 071–079), mfano 062, 068, 071, 075, 077, 078.',
    };
  }

  return { local: s.slice(0, 10) };
}

/** International MSISDN for payment gateways (`2557XXXXXXXX`). */
export function formatPhoneToIntl255(local0: string): string {
  let digits = String(local0 ?? '').replace(/\D/g, '');
  if (digits.startsWith('0')) digits = `255${digits.slice(1)}`;
  else if (!digits.startsWith('255')) digits = `255${digits}`;
  if (digits.length > 12) digits = digits.slice(0, 12);
  return digits;
}

/**
 * Phone formats to try with ZenoPay (order matters by network).
 * Avoids sending duplicate STK when the first attempt already succeeded upstream.
 */
export function phoneCandidatesForPaymentApi(local0: string): string[] {
  const local0fmt = toLocal0Digits(local0);
  if (!isValidTzMobileLocal0(local0fmt)) return [local0fmt].filter(Boolean);
  const intl255 = formatPhoneToIntl255(local0fmt);
  const network = detectTzMobileNetwork(local0fmt);

  let ordered: string[];
  if (network === 'vodacom') ordered = [intl255, local0fmt];
  else if (network === 'halotel') ordered = [local0fmt, intl255];
  else if (network === 'airtel' || network === 'tigo_yas') ordered = [local0fmt, intl255];
  else ordered = [local0fmt, intl255];

  return [...new Set(ordered.filter((p) => p.length > 0))];
}

/**
 * SonicPesa create_order phone formats (differs from Zeno — no wallet `provider` field).
 * Halopesa (061–063) often rejects `255…`; Airtel/Vodacom/Tigo expect `255…` per Sonic docs.
 */
export function phoneCandidatesForSonicPesaApi(local0: string): string[] {
  const local0fmt = toLocal0Digits(local0);
  if (!isValidTzMobileLocal0(local0fmt)) return [local0fmt].filter(Boolean);
  const intl255 = formatPhoneToIntl255(local0fmt);
  if (detectTzMobileNetwork(local0fmt) === 'halotel') {
    return [...new Set([local0fmt, intl255].filter((p) => p.length > 0))];
  }
  return [...new Set([intl255, local0fmt].filter((p) => p.length > 0))];
}

export type ZenoPaymentAttempt = { phone: string; provider?: string };

/**
 * Ordered ZenoPay create attempts — auto-routing first (best for Tigo/Airtel),
 * then explicit wallet hints, then alternate MSISDN format.
 */
export function buildZenoPaymentAttempts(localPhone0: string): ZenoPaymentAttempt[] {
  const local = toLocal0Digits(localPhone0);
  const phones = isValidTzMobileLocal0(local)
    ? phoneCandidatesForPaymentApi(local)
    : [local].filter(Boolean);
  const explicitProviders = zenoWalletProviderCandidates(local);
  const out: ZenoPaymentAttempt[] = [];
  const seen = new Set<string>();
  const add = (phone: string, provider?: string) => {
    const key = `${phone}\0${provider ?? ''}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push(provider ? { phone, provider } : { phone });
  };

  if (process.env.ZENO_SEND_PROVIDER !== '0') {
    for (const phone of phones) add(phone);
  }

  const primary = phones[0];
  if (primary) {
    for (const provider of explicitProviders) add(primary, provider);
  }

  const alt = phones[1];
  if (alt) {
    if (process.env.ZENO_SEND_PROVIDER !== '0') add(alt);
    const hint = zenoWalletProviderForLocalPhone(local);
    if (hint) add(alt, hint);
  }

  return out.length > 0 ? out : phones.map((phone) => ({ phone }));
}

/** Explicit ZenoPay wallet provider strings to try after auto-routing. */
export function zenoWalletProviderCandidates(localPhone0: string): string[] {
  if (process.env.ZENO_SEND_PROVIDER === '0') return [];
  const p = toLocal0Digits(localPhone0);
  const out: string[] = [];
  const add = (v?: string) => {
    if (!v) return;
    const s = v.trim();
    if (!s || out.includes(s)) return;
    out.push(s);
  };

  add(zenoWalletProviderForLocalPhone(p));

  switch (detectTzMobileNetwork(p)) {
    case 'halotel':
      add('HALOPESA');
      add('HALOTEL PESA');
      break;
    case 'vodacom':
      add('M-PESA');
      add('MPESA');
      add('VODACOM');
      break;
    case 'airtel':
      add('AIRTELMONEY');
      add('AIRTEL MONEY');
      add('AIRTEL');
      break;
    case 'tigo_yas':
      add('TIGOPESA');
      add('TIGO PESA');
      add('MIXX BY YAS');
      add('MIXX');
      add('YAS PESA');
      add('YAS');
      add('TIGO');
      break;
    case 'cootel':
    case 'smile':
    case 'mo_mobile':
    case 'ttcl':
    case 'unknown':
      add('TIGOPESA');
      add('M-PESA');
      add('AIRTELMONEY');
      add('AIRTEL MONEY');
      break;
  }
  return out;
}

/** ZenoPay wallet provider hint from local `0…` number. */
export function zenoWalletProviderForLocalPhone(localPhone0: string): string | undefined {
  const p = toLocal0Digits(localPhone0);
  switch (detectTzMobileNetwork(p)) {
    case 'halotel': {
      const v = process.env.ZENO_HALOTEL_WALLET_PROVIDER;
      return typeof v === 'string' && v.trim() ? v.trim() : 'HALOPESA';
    }
    case 'vodacom': {
      if (process.env.ZENO_VODACOM_SEND_PROVIDER === '0') return undefined;
      const v = process.env.ZENO_VODACOM_WALLET_PROVIDER;
      return typeof v === 'string' && v.trim() ? v.trim() : 'M-PESA';
    }
    case 'tigo_yas': {
      const v = process.env.ZENO_TIGO_WALLET_PROVIDER;
      return typeof v === 'string' && v.trim() ? v.trim() : 'TIGOPESA';
    }
    case 'airtel': {
      const v = process.env.ZENO_AIRTEL_WALLET_PROVIDER;
      return typeof v === 'string' && v.trim() ? v.trim() : 'AIRTELMONEY';
    }
    case 'cootel':
    case 'smile':
    case 'mo_mobile':
    case 'ttcl':
    case 'unknown': {
      const v = process.env.ZENO_TIGO_WALLET_PROVIDER;
      return typeof v === 'string' && v.trim() ? v.trim() : 'TIGOPESA';
    }
    default:
      return undefined;
  }
}
