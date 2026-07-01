import { createHmac, timingSafeEqual } from 'crypto';
import { env } from '../config/env';
import { HttpError } from '../middleware/errorHandler';
import {
  isMobileMoneyStkSendFailure,
  isPaymentCreateRetryable,
  isPaymentRateLimitError,
  paymentRateLimitUserMessage,
} from '../lib/paymentProviderErrors';
import {
  detectTzMobileNetwork,
  formatPhoneToIntl255,
  isHalotelLocalPhone,
  phoneCandidatesForSonicPesaApi,
  sonicChannelHintsForNetwork,
} from '../lib/tzPhone';

const SONIC_API_BASE = 'https://api.sonicpesa.com/api/v1';
const SONIC_HTTP_TIMEOUT_MS = 22_000;
const SONIC_HTTP_RETRY_TIMEOUT_MS = 12_000;
/** Cap gateway round-trips so the mobile client does not time out before we finish. */
const MAX_SONIC_CREATE_ATTEMPTS = 8;
const SONIC_RETRY_DELAY_MS = 250;

const sonicRetryDelay = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

const SONIC_PAID_STATUSES = new Set([
  'SUCCESS',
  'COMPLETED',
  'PAID',
  'COMPLETE',
  'SUCCEEDED',
  'APPROVED',
  'CONFIRMED',
  'SETTLED',
]);

export function getSonicPesaRequestHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'X-API-KEY': env.sonicPesaApiKey,
    Accept: 'application/json',
  };
  if (env.sonicPesaSecretKey.trim()) {
    headers['X-SECRET-KEY'] = env.sonicPesaSecretKey.trim();
  }
  return headers;
}

export function ensureSonicPesaConfigured(): void {
  if (!env.sonicPesaApiKey.trim()) {
    throw new HttpError(
      500,
      'SONICPESA_API_KEY is not configured on the server',
      'SONIC_KEY_MISSING',
    );
  }
}

async function gatewayFetchJson(
  url: string,
  init: RequestInit,
  timeoutMs = SONIC_HTTP_TIMEOUT_MS,
): Promise<{ response: Response; data: Record<string, unknown> }> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...init, signal: ctrl.signal });
    const text = await res.text();
    let data: Record<string, unknown> = {};
    try {
      data = (JSON.parse(text) as Record<string, unknown>) ?? {};
    } catch {
      data = { status: 'error', message: text.slice(0, 200) };
    }
    return { response: res, data };
  } finally {
    clearTimeout(t);
  }
}

export function extractSonicResponseMessage(data: Record<string, unknown>): string {
  const nest = data.data;
  const row =
    nest && typeof nest === 'object' && !Array.isArray(nest)
      ? (nest as Record<string, unknown>)
      : Array.isArray(nest) && nest.length > 0 && typeof nest[0] === 'object'
        ? (nest[0] as Record<string, unknown>)
        : null;
  for (const v of [
    data.message,
    data.error,
    data.detail,
    row?.message,
    row?.error,
  ]) {
    const s = String(v ?? '').trim();
    if (s) return s;
  }
  return '';
}

export function extractSonicResponseCode(data: Record<string, unknown>): string {
  const nest = data.data;
  const row =
    nest && typeof nest === 'object' && !Array.isArray(nest)
      ? (nest as Record<string, unknown>)
      : null;
  return String(
    data.resultcode ??
      data.result_code ??
      data.code ??
      row?.resultcode ??
      row?.result_code ??
      row?.code ??
      '',
  ).trim();
}

export function isSonicInitiateSuccess(
  sonicData: Record<string, unknown> | null | undefined,
  httpResponse: Response,
): boolean {
  if (!sonicData || typeof sonicData !== 'object') return false;
  const responseMessage = extractSonicResponseMessage(sonicData);
  const responseCode = extractSonicResponseCode(sonicData);
  if (isSonicStkSendFailure(responseMessage, responseCode)) return false;

  const st = String(sonicData.status ?? '')
    .toLowerCase()
    .trim();
  if (st === 'error' || st === 'failed') return false;
  if (st === 'success') return true;
  if (sonicData.success === true) return true;
  const nest = sonicData.data;
  const row =
    nest && typeof nest === 'object' && !Array.isArray(nest)
      ? (nest as Record<string, unknown>)
      : Array.isArray(nest) && nest.length > 0 && typeof nest[0] === 'object'
        ? (nest[0] as Record<string, unknown>)
        : sonicData;
  const orderId = row.order_id ?? row.orderId;
  if (orderId && httpResponse.ok) return true;
  return false;
}

export function extractSonicOrderId(sonicData: Record<string, unknown>): string {
  const nest = sonicData.data;
  const row =
    nest && typeof nest === 'object' && !Array.isArray(nest)
      ? (nest as Record<string, unknown>)
      : Array.isArray(nest) && nest.length > 0 && typeof nest[0] === 'object'
        ? (nest[0] as Record<string, unknown>)
        : sonicData;
  return String(row.order_id ?? row.orderId ?? sonicData.order_id ?? sonicData.orderId ?? '').trim();
}

export function extractSonicPaymentStatus(statusData: Record<string, unknown>): string {
  const d = statusData.data;
  const nest = Array.isArray(d) ? d[0] : d && typeof d === 'object' ? d : null;
  const nestObj = nest && typeof nest === 'object' ? (nest as Record<string, unknown>) : null;
  const candidates = [
    nestObj?.payment_status,
    nestObj?.paymentStatus,
    nestObj?.transaction_status,
    nestObj?.transactionStatus,
    nestObj?.order_status,
    nestObj?.orderStatus,
    nestObj?.status,
    statusData.payment_status,
    statusData.paymentStatus,
    statusData.transaction_status,
    statusData.transactionStatus,
    statusData.status,
  ];
  for (const c of candidates) {
    if (c != null && typeof c !== 'object') {
      const s = String(c).toUpperCase().trim();
      if (s) return s;
    }
  }
  return '';
}

export function isSonicPaymentCompleted(rawUpper: string): boolean {
  if (!rawUpper) return false;
  const u = String(rawUpper).toUpperCase().trim();
  if (SONIC_PAID_STATUSES.has(u)) return true;
  const lower = u.toLowerCase();
  return lower === 'successful' || lower === 'ok' || lower === 'true' || lower === '1';
}

/** True when Sonic status API / webhook body indicates paid even if status string is non-standard. */
export function isSonicRawPaymentCompleted(data: Record<string, unknown>): boolean {
  const ps = extractSonicPaymentStatus(data);
  if (isSonicPaymentCompleted(ps)) return true;
  if (data.success === true) return true;
  const rc = String(data.resultcode ?? data.result_code ?? data.code ?? '').trim();
  if (rc === '000' || rc === '0') {
    const st = String(data.status ?? '').toLowerCase().trim();
    if (st === 'success' || st === 'ok' || st === 'completed' || st === 'paid') return true;
  }
  const nest = data.data;
  if (nest && typeof nest === 'object') {
    const row = Array.isArray(nest) && nest.length > 0 && typeof nest[0] === 'object'
      ? (nest[0] as Record<string, unknown>)
      : (nest as Record<string, unknown>);
    if (row.success === true) return true;
    const nestedPs = extractSonicPaymentStatus({ data: row, status: row.status, payment_status: row.payment_status });
    if (isSonicPaymentCompleted(nestedPs)) return true;
  }
  return false;
}

/** Local 0… for DB; Sonic API often wants 255…. */
export function formatPhoneForSonicPesaApi(local0: string): string {
  if (env.sonicSendLocalPhone) return local0;
  return formatPhoneToIntl255(local0);
}

export function sonicPhoneCandidatesForApi(local0: string): string[] {
  if (env.sonicSendLocalPhone) return [local0];
  return phoneCandidatesForSonicPesaApi(local0);
}

type SonicCreateAttempt = {
  buyer_phone: string;
  channel?: string;
};

/** Best-first phone/channel combos — few attempts, high success rate on first tap. */
function buildSonicCreateAttempts(localPhone: string): SonicCreateAttempt[] {
  const phones = sonicPhoneCandidatesForApi(localPhone);
  const channels = sonicChannelHintsForNetwork(localPhone).slice(0, 2);
  const intl255 = phones[0] ?? '';
  const local0 = phones.length > 1 ? phones[1]! : '';
  const out: SonicCreateAttempt[] = [];
  const seen = new Set<string>();
  const add = (buyer_phone: string, channel?: string) => {
    if (!buyer_phone) return;
    const key = `${buyer_phone}\0${channel ?? ''}`;
    if (seen.has(key)) return;
    seen.add(key);
    out.push(channel ? { buyer_phone, channel } : { buyer_phone });
  };

  if (intl255) add(intl255);
  for (const channel of channels) {
    if (intl255) add(intl255, channel);
  }
  if (local0 && local0 !== intl255) {
    add(local0);
    for (const channel of channels) add(local0, channel);
  }

  return out;
}

const SONIC_CREATE_ENDPOINTS = ['payment/create_order', 'payment/create_order_simple'] as const;

async function postSonicCreateOrder(
  endpoint: string,
  attempt: SonicCreateAttempt,
  args: { buyerEmail: string; buyerName: string; amountTzs: number },
  timeoutMs = SONIC_HTTP_TIMEOUT_MS,
): Promise<{ response: Response; data: Record<string, unknown> }> {
  const payload: Record<string, unknown> = {
    buyer_email: args.buyerEmail,
    buyer_name: args.buyerName,
    buyer_phone: attempt.buyer_phone,
    amount: args.amountTzs,
    currency: 'TZS',
  };
  if (attempt.channel) payload.channel = attempt.channel;
  return gatewayFetchJson(`${SONIC_API_BASE}/${endpoint}`, {
    method: 'POST',
    headers: getSonicPesaRequestHeaders(),
    body: JSON.stringify(payload),
  }, timeoutMs);
}


export function isSonicStkSendFailure(rawMessage: string, rawCode: string): boolean {
  return isMobileMoneyStkSendFailure(rawMessage, rawCode);
}

function isSonicCreateRetryable(errorMessage: string, errorCode: string): boolean {
  return isPaymentCreateRetryable(errorMessage, errorCode);
}

/** Swahili user-facing message for SonicPesa checkout failures. */
export function mapSonicInitiateUserError(
  localPhone: string,
  rawMessage: string,
  rawCode: string,
): string {
  const code = String(rawCode ?? '').trim();
  const msg = String(rawMessage || '').trim();
  const hayajatumika = /hayajatumika|hayajaweza kutumika|hayajaweza kutuma/i.test(msg);
  if (code === '103' || /ongoing ussd/i.test(msg)) {
    return 'Simu yako ina USSD nyingine zinazoendelea. Funga dirisha la malipo/USSD kwenye simu, subiri sekunde 30, kisha jaribu tena.';
  }
  if (isPaymentRateLimitError(msg, code)) {
    return paymentRateLimitUserMessage();
  }
  if (isSonicStkSendFailure(msg, code) || hayajatumika) {
    if (isHalotelLocalPhone(localPhone)) {
      return 'Halopesa (061–063) haikupokea ombi. Hakikisha nambari ni sahihi, una salio, na mtandao wa Halopesa unafanya kazi, kisha jaribu tena.';
    }
    const network = detectTzMobileNetwork(localPhone);
    if (network === 'airtel') {
      return 'Hatukuweza kutuma ombi la Airtel Money kwenye simu yako. Hakikisha nambari ni sahihi, una salio, na Airtel Money inafanya kazi, kisha jaribu tena.';
    }
    if (network === 'tigo_yas') {
      return 'Hatukuweza kutuma ombi la Tigo/Yas kwenye simu yako. Hakikisha nambari ni sahihi, una salio, na TigoPesa/Mixx inafanya kazi, kisha jaribu tena.';
    }
    if (network === 'vodacom') {
      return 'Hatukuweza kutuma ombi la M-Pesa kwenye simu yako. Hakikisha nambari ni sahihi, una salio, na M-Pesa inafanya kazi, kisha jaribu tena.';
    }
    return 'Hatukuweza kutuma ombi la malipo kwenye simu yako. Hakikisha nambari ni sahihi na mtandao wa pesa unafanya kazi, kisha jaribu tena.';
  }
  if (/invalid phone|invalid msisdn|wrong number|nambari/i.test(`${msg} ${code}`)) {
    return 'Nambari ya simu si sahihi kwa malipo ya simu. Tumia nambari 10 za Tanzania (mfano 0712345678).';
  }
  return msg || 'Malipo hayajatumika. Jaribu tena baada ya muda mfupi.';
}

export type SonicCreateResult = {
  ok: boolean;
  orderId: string;
  message: string;
  raw: Record<string, unknown>;
  errorMessage?: string;
  errorCode?: string;
};

export async function tryCreateSonicOrder(args: {
  buyerEmail: string;
  buyerName: string;
  localPhone: string;
  amountTzs: number;
}): Promise<SonicCreateResult> {
  ensureSonicPesaConfigured();
  const attempts = buildSonicCreateAttempts(args.localPhone);
  let last: { response: Response; data: Record<string, unknown> } = {
    response: new Response(null, { status: 500 }),
    data: { status: 'error', message: 'Failed to start SonicPesa payment' },
  };

  let tried = 0;
  outer:
  for (const endpoint of SONIC_CREATE_ENDPOINTS) {
    for (const attempt of attempts) {
      if (tried >= MAX_SONIC_CREATE_ATTEMPTS) break outer;
      tried++;
      const timeoutMs = tried === 1 ? SONIC_HTTP_TIMEOUT_MS : SONIC_HTTP_RETRY_TIMEOUT_MS;
      try {
        if (tried > 1) await sonicRetryDelay(SONIC_RETRY_DELAY_MS);
        last = await postSonicCreateOrder(endpoint, attempt, args, timeoutMs);
        const responseMessage = extractSonicResponseMessage(last.data);
        const responseCode = extractSonicResponseCode(last.data);

        if (isSonicInitiateSuccess(last.data, last.response)) {
          const orderId = extractSonicOrderId(last.data);
          if (orderId && !isSonicStkSendFailure(responseMessage, responseCode)) {
            return {
              ok: true,
              orderId,
              message: String(
                last.data.message ?? 'Request in progress. You will receive a prompt on your phone.',
              ),
              raw: last.data,
            };
          }
          if (!isSonicCreateRetryable(responseMessage, responseCode)) {
            continue;
          }
          continue;
        }

        const errorMessage = responseMessage || 'Failed to start SonicPesa payment';
        const errorCode = responseCode;
        if (isPaymentRateLimitError(errorMessage, errorCode)) {
          return {
            ok: false,
            orderId: '',
            message: paymentRateLimitUserMessage(),
            raw: last.data,
            errorMessage: paymentRateLimitUserMessage(),
            errorCode,
          };
        }
        if (!isSonicCreateRetryable(errorMessage, errorCode)) {
          continue;
        }
      } catch (e) {
        last = {
          response: new Response(null, { status: 502 }),
          data: { status: 'error', message: e instanceof Error ? e.message : String(e) },
        };
      }
    }
  }

  const errorMessage = extractSonicResponseMessage(last.data) || 'Failed to start SonicPesa payment';
  const errorCode = extractSonicResponseCode(last.data);
  if (isPaymentRateLimitError(errorMessage, errorCode)) {
    return {
      ok: false,
      orderId: '',
      message: paymentRateLimitUserMessage(),
      raw: last.data,
      errorMessage: paymentRateLimitUserMessage(),
      errorCode,
    };
  }
  return {
    ok: false,
    orderId: '',
    message: errorMessage,
    raw: last.data,
    errorMessage,
    errorCode,
  };
}

export async function createSonicOrder(args: {
  buyerEmail: string;
  buyerName: string;
  localPhone: string;
  amountTzs: number;
}): Promise<{
  orderId: string;
  message: string;
  raw: Record<string, unknown>;
}> {
  const out = await tryCreateSonicOrder(args);
  if (!out.ok) {
    throw new HttpError(400, out.errorMessage ?? 'Failed to start SonicPesa payment', 'SONIC_CREATE_FAILED');
  }
  return { orderId: out.orderId, message: out.message, raw: out.raw };
}

export async function fetchSonicOrderStatus(orderId: string): Promise<{
  ok: boolean;
  paymentStatus: string;
  raw: Record<string, unknown>;
}> {
  ensureSonicPesaConfigured();
  const { response, data } = await gatewayFetchJson(`${SONIC_API_BASE}/payment/order_status`, {
    method: 'POST',
    headers: getSonicPesaRequestHeaders(),
    body: JSON.stringify({ order_id: orderId }),
  });
  const ps = extractSonicPaymentStatus(data);
  return { ok: response.ok, paymentStatus: ps, raw: data };
}

function timingSafeEqualHexOrString(a: string, b: string): boolean {
  const x = a.trim().toLowerCase();
  const y = b.trim().toLowerCase();
  const xa = x.includes('=') ? (x.split('=').pop()?.trim() ?? x) : x;
  const yb = y.includes('=') ? (y.split('=').pop()?.trim() ?? y) : y;
  if (xa.length !== yb.length) return false;
  try {
    const bx = Buffer.from(xa, 'hex');
    const by = Buffer.from(yb, 'hex');
    if (bx.length > 0 && bx.length === by.length && bx.length === xa.length / 2) {
      return timingSafeEqual(bx, by);
    }
  } catch {
    /* fall through */
  }
  const bufA = Buffer.from(xa, 'utf8');
  const bufB = Buffer.from(yb, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

export function verifySonicPesaWebhookHmac(rawBodyString: string, headerValue: string | undefined): boolean {
  const secret = env.sonicPesaWebhookSecret.trim();
  if (!secret || typeof headerValue !== 'string' || !headerValue.trim()) return false;
  if (!rawBodyString.length) return false;
  const expected = createHmac('sha256', secret).update(rawBodyString, 'utf8').digest('hex');
  return (
    timingSafeEqualHexOrString(headerValue, expected) ||
    timingSafeEqualHexOrString(headerValue, `sha256=${expected}`)
  );
}

export function extractSonicWebhookPaid(payload: Record<string, unknown>): {
  orderId: string | null;
  paid: boolean;
} {
  const d = payload.data;
  const nest =
    d && typeof d === 'object' && !Array.isArray(d)
      ? (d as Record<string, unknown>)
      : Array.isArray(d) && d.length > 0 && typeof d[0] === 'object'
        ? (d[0] as Record<string, unknown>)
        : null;
  const orderId = String(
    payload.order_id ??
      payload.orderId ??
      nest?.order_id ??
      nest?.orderId ??
      payload.reference ??
      payload.reference_id ??
      payload.invoice_id ??
      nest?.reference ??
      '',
  ).trim();

  const st = String(nest?.status ?? nest?.payment_status ?? nest?.paymentStatus ?? payload.status ?? '')
    .toUpperCase()
    .trim();
  const ev = String(payload.event ?? payload.type ?? '')
    .toLowerCase()
    .trim();
  let paid = SONIC_PAID_STATUSES.has(st) || isSonicRawPaymentCompleted(payload);
  if (!paid && ev) {
    paid =
      ev === 'payment.success' ||
      ev === 'payment.completed' ||
      ev === 'payment_completed' ||
      ev === 'invoice.paid' ||
      ev === 'charge.succeeded';
  }
  return { orderId: orderId || null, paid };
}
