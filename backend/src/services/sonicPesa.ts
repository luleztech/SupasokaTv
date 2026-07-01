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
  isVodacomMpesaLocalPhone,
  toLocal0Digits,
} from '../lib/tzPhone';

const SONIC_API_BASE = 'https://api.sonicpesa.com/api/v1';
/** Docs: Push USSD via create_order — gateway auto-detects wallet from 255… MSISDN. */
const SONIC_CREATE_ORDER_TIMEOUT_MS = 28_000;
/** Docs: create_order_simple long-polls up to ~45s — client timeout ≥60s. */
const SONIC_CREATE_SIMPLE_TIMEOUT_MS = 62_000;
const SONIC_RETRY_DELAY_MS = 400;
const SONIC_USSD_BUSY_DELAY_MS = 2_500;

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
  timeoutMs = SONIC_CREATE_ORDER_TIMEOUT_MS,
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

export function isSonicPushUssdSentMessage(message: string): boolean {
  const m = String(message ?? '').toLowerCase();
  return (
    /push ussd sent|ussd sent|sent to your phone|payment order created successfully/i.test(m) ||
    /you will receive a prompt/i.test(m)
  );
}

export function isSonicInitiateSuccess(
  sonicData: Record<string, unknown> | null | undefined,
  httpResponse: Response,
): boolean {
  if (!sonicData || typeof sonicData !== 'object') return false;
  const responseMessage = extractSonicResponseMessage(sonicData);
  const responseCode = extractSonicResponseCode(sonicData);
  const orderId = extractSonicOrderId(sonicData);

  if (orderId && isSonicPushUssdSentMessage(responseMessage)) return true;

  if (isSonicStkSendFailure(responseMessage, responseCode) && !isSonicPushUssdSentMessage(responseMessage)) {
    return false;
  }

  const st = String(sonicData.status ?? '')
    .toLowerCase()
    .trim();
  if (st === 'error' || st === 'failed') return false;
  if (st === 'success' && orderId) return true;
  if (sonicData.success === true && orderId) return true;
  if (orderId && httpResponse.ok && isSonicPushUssdSentMessage(responseMessage)) return true;
  if (orderId && httpResponse.ok && st !== 'error' && st !== 'failed') return true;
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

/** Docs-compliant MSISDN for buyer_phone: always 255XXXXXXXXX first, national 0… as fallback. */
export function sonicBuyerPhonesForApi(localPhone: string): string[] {
  const local0 = toLocal0Digits(localPhone);
  const intl255 = formatPhoneToIntl255(local0);
  if (env.sonicSendLocalPhone) return [local0];
  const out = [intl255];
  if (local0.startsWith('0') && local0 !== intl255) out.push(local0);
  return [...new Set(out.filter(Boolean))];
}

/** Local 0… for DB. */
export function formatPhoneForSonicPesaApi(local0: string): string {
  if (env.sonicSendLocalPhone) return toLocal0Digits(local0);
  return formatPhoneToIntl255(local0);
}

export function sonicPhoneCandidatesForApi(local0: string): string[] {
  return sonicBuyerPhonesForApi(local0);
}

type SonicCreateStep = {
  endpoint: 'payment/create_order' | 'payment/create_order_simple';
  buyer_phone: string;
  timeoutMs: number;
};

/**
 * SonicPesa docs: POST create_order with buyer_email, buyer_name, buyer_phone (255…),
 * amount, currency — no channel; gateway auto-sends Push USSD. Fallback: create_order_simple.
 */
function buildSonicCreateSteps(localPhone: string): SonicCreateStep[] {
  const phones = sonicBuyerPhonesForApi(localPhone);
  const primary = phones[0] ?? formatPhoneToIntl255(localPhone);
  const steps: SonicCreateStep[] = [
    {
      endpoint: 'payment/create_order',
      buyer_phone: primary,
      timeoutMs: SONIC_CREATE_ORDER_TIMEOUT_MS,
    },
    {
      endpoint: 'payment/create_order_simple',
      buyer_phone: primary,
      timeoutMs: SONIC_CREATE_SIMPLE_TIMEOUT_MS,
    },
  ];
  const fallback = phones[1];
  if (fallback && fallback !== primary) {
    steps.push({
      endpoint: 'payment/create_order',
      buyer_phone: fallback,
      timeoutMs: SONIC_CREATE_ORDER_TIMEOUT_MS,
    });
  }
  return steps;
}

function isSonicUssdBusy(responseMessage: string, responseCode: string): boolean {
  const code = String(responseCode ?? '').trim();
  const msg = String(responseMessage ?? '').toLowerCase();
  return code === '103' || /ongoing ussd|ussd session|session busy/i.test(msg);
}

async function postSonicCreateOrder(
  step: SonicCreateStep,
  args: { buyerEmail: string; buyerName: string; amountTzs: number },
): Promise<{ response: Response; data: Record<string, unknown> }> {
  const payload: Record<string, unknown> = {
    buyer_email: args.buyerEmail,
    buyer_name: args.buyerName,
    buyer_phone: step.buyer_phone,
    amount: args.amountTzs,
    currency: 'TZS',
  };
  return gatewayFetchJson(
    `${SONIC_API_BASE}/${step.endpoint}`,
    {
      method: 'POST',
      headers: getSonicPesaRequestHeaders(),
      body: JSON.stringify(payload),
    },
    step.timeoutMs,
  );
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
    const network = detectTzMobileNetwork(toLocal0Digits(localPhone));
    if (network === 'airtel') {
      return 'Hatukuweza kutuma ombi la Airtel Money kwenye simu yako. Hakikisha nambari ni sahihi, una salio, na Airtel Money inafanya kazi, kisha jaribu tena.';
    }
    if (network === 'tigo_yas') {
      return 'Hatukuweza kutuma ombi la Tigo/Yas kwenye simu yako. Hakikisha nambari ni sahihi, una salio, na TigoPesa/Mixx inafanya kazi, kisha jaribu tena.';
    }
    if (network === 'vodacom' || isVodacomMpesaLocalPhone(localPhone)) {
      return 'Hatukuweza kutuma ombi la M-Pesa (Vodacom) kwenye simu yako. Hakikisha nambari 074, 075, 076 au 079 ni sahihi, una salio, na M-Pesa inafanya kazi, kisha jaribu tena.';
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
  const steps = buildSonicCreateSteps(args.localPhone);
  let last: { response: Response; data: Record<string, unknown> } = {
    response: new Response(null, { status: 500 }),
    data: { status: 'error', message: 'Failed to start SonicPesa payment' },
  };

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]!;
    try {
      if (i > 0) await sonicRetryDelay(SONIC_RETRY_DELAY_MS);
      last = await postSonicCreateOrder(step, args);
      const responseMessage = extractSonicResponseMessage(last.data);
      const responseCode = extractSonicResponseCode(last.data);

      if (isSonicUssdBusy(responseMessage, responseCode)) {
        await sonicRetryDelay(SONIC_USSD_BUSY_DELAY_MS);
        last = await postSonicCreateOrder(step, args);
      }

      const retryMessage = extractSonicResponseMessage(last.data);
      const retryCode = extractSonicResponseCode(last.data);

      if (isSonicInitiateSuccess(last.data, last.response)) {
        const orderId = extractSonicOrderId(last.data);
        if (
          orderId &&
          (isSonicPushUssdSentMessage(retryMessage) ||
            !isSonicStkSendFailure(retryMessage, retryCode))
        ) {
          return {
            ok: true,
            orderId,
            message: String(
              last.data.message ??
                'Payment order created successfully! Push USSD sent to your phone.',
            ),
            raw: last.data,
          };
        }
        if (!isSonicCreateRetryable(retryMessage, retryCode)) continue;
        continue;
      }

      const errorMessage = retryMessage || 'Failed to start SonicPesa payment';
      const errorCode = retryCode;
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
      if (!isSonicCreateRetryable(errorMessage, errorCode)) continue;
    } catch (e) {
      last = {
        response: new Response(null, { status: 502 }),
        data: { status: 'error', message: e instanceof Error ? e.message : String(e) },
      };
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
    errorMessage: mapSonicInitiateUserError(args.localPhone, errorMessage, errorCode),
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
