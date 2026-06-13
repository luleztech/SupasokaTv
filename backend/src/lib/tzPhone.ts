/**
 * Tanzania mobile MSISDN (national format `0XXXXXXXXX`, 10 digits).
 * Prefix list aligned with TCRA numbering (061–079 operational / assigned ranges).
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

export type NormalizePhoneResult = { local?: string; error?: string };

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
        'Nambari ya simu lazima iwe nambari 10 za Tanzania: anza kwa 0 kisha tarakimu 9 (mfano 0701234567 au 0712345678).',
    };
  }

  const hasValidPrefix = TZ_MOBILE_PREFIXES.some((p) => s.startsWith(p));
  if (!hasValidPrefix) {
    return {
      error:
        'Nambari hii haionekani kuwa ya mtandao wa simu Tanzania unaotumika kwa malipo. Tumia nambari halali (mfano 061–079).',
    };
  }

  return { local: s };
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
 * Phone formats to try with Zeno/Sonic (order matters by network).
 * Avoids sending duplicate STK when the first attempt already succeeded upstream.
 */
export function phoneCandidatesForPaymentApi(local0: string): string[] {
  const local0fmt = String(local0 ?? '').replace(/\D/g, '').slice(0, 10);
  if (!/^0[1-9]\d{8}$/.test(local0fmt)) return [local0fmt].filter(Boolean);
  const intl255 = formatPhoneToIntl255(local0fmt);

  const isHalotel = /^06[123]/.test(local0fmt);
  const isVodacom = /^07[45679]/.test(local0fmt) && !/^078/.test(local0fmt);
  const isAirtel = /^06[89]/.test(local0fmt) || /^078/.test(local0fmt);

  let ordered: string[];
  if (isHalotel) ordered = [local0fmt, intl255];
  else if (isVodacom) ordered = [intl255, local0fmt];
  else if (isAirtel) ordered = [local0fmt, intl255];
  else ordered = [local0fmt, intl255];

  return [...new Set(ordered.filter((p) => p.length > 0))];
}

/** Wallet providers to try (primary first, then auto-detect). */
export function zenoWalletProviderCandidates(localPhone0: string): (string | undefined)[] {
  if (process.env.ZENO_SEND_PROVIDER === '0') return [undefined];
  const p = String(localPhone0 || '').trim();
  const out: (string | undefined)[] = [];
  const add = (v?: string) => {
    if (v == null) {
      if (!out.some((x) => x === undefined)) out.push(undefined);
      return;
    }
    const s = v.trim();
    if (!s || out.includes(s)) return;
    out.push(s);
  };

  add(zenoWalletProviderForLocalPhone(p));

  if (/^06[123]/.test(p)) {
    add('HALOPESA');
    add('HALOTEL PESA');
  } else if (/^07[45679]/.test(p) && !/^078/.test(p)) {
    add('M-PESA');
    add('MPESA');
  } else if (/^06[589]/.test(p) || /^078/.test(p)) {
    add('AIRTEL MONEY');
    add('AIRTELMONEY');
  } else if (['065', '067', '070', '071', '077'].some((pre) => p.startsWith(pre))) {
    add('TIGOPESA');
    add('TIGO PESA');
    add('TIGO');
  } else {
    add('TIGOPESA');
    add('M-PESA');
    add('AIRTEL MONEY');
  }
  add(undefined);
  return out;
}

/** ZenoPay wallet provider hint from local `07…` number. */
export function zenoWalletProviderForLocalPhone(localPhone0: string): string | undefined {
  const p = String(localPhone0 || '');
  if (p.startsWith('061') || p.startsWith('062') || p.startsWith('063')) {
    const v = process.env.ZENO_HALOTEL_WALLET_PROVIDER;
    return typeof v === 'string' && v.trim() ? v.trim() : 'HALOPESA';
  }
  if (p.startsWith('074') || p.startsWith('075') || p.startsWith('076') || p.startsWith('079')) {
    if (process.env.ZENO_VODACOM_SEND_PROVIDER === '0') return undefined;
    const v = process.env.ZENO_VODACOM_WALLET_PROVIDER;
    return typeof v === 'string' && v.trim() ? v.trim() : 'M-PESA';
  }
  if (
    p.startsWith('065') ||
    p.startsWith('067') ||
    p.startsWith('070') ||
    p.startsWith('071') ||
    p.startsWith('077')
  ) {
    const v = process.env.ZENO_TIGO_WALLET_PROVIDER;
    return typeof v === 'string' && v.trim() ? v.trim() : 'TIGOPESA';
  }
  if (p.startsWith('068') || p.startsWith('069') || p.startsWith('078')) {
    const v = process.env.ZENO_AIRTEL_WALLET_PROVIDER;
    return typeof v === 'string' && v.trim() ? v.trim() : 'AIRTEL MONEY';
  }
  // TTCL, Smile, CooTel, MO Mobile — try Tigo rail (common aggregator path in TZ).
  if (p.startsWith('073') || p.startsWith('066') || p.startsWith('064') || p.startsWith('072')) {
    const v = process.env.ZENO_TIGO_WALLET_PROVIDER;
    return typeof v === 'string' && v.trim() ? v.trim() : 'TIGOPESA';
  }
  return undefined;
}
