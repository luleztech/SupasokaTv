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
  '072', // MO Mobile (legacy; may use M-Pesa via portability)
  '073', // TTCL
  '074', '075', '076', '079', // Vodacom M-Pesa
] as const;

/** Vodacom Tanzania M-Pesa prefixes (074, 075, 076, 079). */
export const VODACOM_MPESA_PREFIXES = ['074', '075', '076', '079'] as const;

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

/** Vodacom M-Pesa numbers: 074, 075, 076, 079. */
export function isVodacomMpesaLocalPhone(local0: string): boolean {
  const p = toLocal0Digits(local0);
  return VODACOM_MPESA_PREFIXES.some((pre) => p.startsWith(pre));
}

export function detectTzMobileNetwork(local0: string): TzMobileNetwork {
  const p = toLocal0Digits(local0);
  if (/^06[123]/.test(p)) return 'halotel';
  if (p.startsWith('064')) return 'cootel';
  if (['065', '067', '070', '071', '077'].some((pre) => p.startsWith(pre))) return 'tigo_yas';
  if (p.startsWith('066')) return 'smile';
  if (/^06[89]/.test(p) || p.startsWith('078')) return 'airtel';
  if (p.startsWith('072')) return 'mo_mobile';
  if (isVodacomMpesaLocalPhone(p)) return 'vodacom';
  if (p.startsWith('073')) return 'ttcl';
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
  if (s.toUpperCase().startsWith('+255')) {
    s = `0${s.slice(4)}`;
  } else if (s.toUpperCase().startsWith('00255')) {
    s = `0${s.slice(5)}`;
  } else if (/^255\d{9,}$/.test(s.replace(/\D/g, ''))) {
    const digits = s.replace(/\D/g, '');
    s = `0${digits.slice(3, 12)}`;
  }

  s = s.replace(/\D/g, '');

  // Typo `007…` → `07…`; reject foreign `00…` country codes (not `00255`).
  while (s.startsWith('00') && s.length > 10 && /^00[67]/.test(s)) {
    s = `0${s.slice(2)}`;
  }
  if (s.startsWith('00') && !s.startsWith('00255')) {
    if (/^00[67]/.test(s)) {
      s = `0${s.slice(2)}`;
    } else {
      return {
        error:
          'Malipo yanatumwa kwa nambari za simu za Tanzania pekee. Tumia muundo wa ndani unaoanza na 0 (mfano 0712345678).',
      };
    }
  }

  if (/^[1-9]\d{8}$/.test(s)) {
    s = `0${s}`;
  }

  if (s.length > 10) {
    s = s.slice(0, 10);
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
        'Nambari hii si ya simu ya Tanzania. Tumia nambari halali ya ndani (061–069, 070–079), mfano 062, 068, 071, 074, 075, 077, 078, 079.',
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
 * SonicPesa buyer_phone per official API docs — international 255XXXXXXXXX first.
 * @see https://api.sonicpesa.com/api/v1/payment/create_order
 */
export function phoneCandidatesForSonicPesaApi(local0: string): string[] {
  const local0fmt = toLocal0Digits(local0);
  if (!isValidTzMobileLocal0(local0fmt)) return [local0fmt].filter(Boolean);
  const intl255 = formatPhoneToIntl255(local0fmt);
  // SonicPesa docs: 255XXXXXXXXX first; national 0… as fallback.
  const ordered = [intl255, local0fmt];

  return [...new Set(ordered.filter((p) => p.length > 0))];
}

/** Preferred SonicPesa `channel` values per operator (from gateway webhooks/docs). */
export function sonicChannelHintsForNetwork(local0: string): string[] {
  const network = detectTzMobileNetwork(toLocal0Digits(local0));
  switch (network) {
    case 'vodacom':
    case 'mo_mobile':
      return [
        'MPESA',
        'M-PESA',
        'VODACOMMPESA',
        'VODACOM MPESA',
        'VODACOM',
        'MPESATZ',
      ];
    case 'tigo_yas':
      return ['TIGOPESATZ', 'TIGOPESA', 'TIGO PESA', 'MIXX BY YAS', 'MIXX', 'YAS', 'MIC'];
    case 'airtel':
      return ['AIRTELMONEY', 'AIRTEL MONEY', 'AIRTEL', 'AIRTELMONEYTZ'];
    case 'halotel':
      return ['HALOPESATZ', 'HALOPESA', 'HALO PESA', 'HALOTEL', 'HALOPESA TZ'];
    case 'cootel':
      return ['COOTEL', 'COO TEL'];
    case 'smile':
      return ['SMILE', 'SMILE MONEY'];
    case 'ttcl':
      return ['TTCL', 'TTCL PESA'];
    default:
      return [];
  }
}

export function isHalotelLocalPhone(local0: string): boolean {
  const p = toLocal0Digits(local0);
  return p.startsWith('061') || p.startsWith('062') || p.startsWith('063');
}
