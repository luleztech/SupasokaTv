import { createHmac, timingSafeEqual } from 'crypto';
import { env } from '../config/env';
import { HttpError } from '../middleware/errorHandler';
import {
  isPaymentRateLimitError,
  isRecoverablePaymentCreateError,
  paymentRateLimitUserMessage,
} from '../lib/paymentProviderErrors';
import { formatPhoneToIntl255, phoneCandidatesForPaymentApi } from '../lib/tzPhone';

const SONIC_API_BASE = 'https://api.sonicpesa.com/api/v1';
const SONIC_HTTP_TIMEOUT_MS = 28_000;

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

export function isSonicInitiateSuccess(
  sonicData: Record<string, unknown> | null | undefined,
  httpResponse: Response,
): boolean {
  if (!sonicData || typeof sonicData !== 'object') return false;
  const st = String(sonicData.status ?? '')
    .toLowerCase()
    .trim();
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
  if (orderId && (httpResponse.ok || st !== 'error')) return true;
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
    nestObj?.status,
    statusData.payment_status,
    statusData.paymentStatus,
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
  return phoneCandidatesForPaymentApi(local0);
}

const SONIC_STK_FAILURE_CODES = new Set([
  '9012', '999', '103', '9009', '90009', '500', '502', '503', '504', '408', '429',
]);

export function isSonicStkSendFailure(rawMessage: string, rawCode: string): boolean {
  const msg = String(rawMessage || '').trim();
  const code = String(rawCode ?? '').trim();
  const combined = `${msg} ${code}`.toLowerCase();
  if (code && SONIC_STK_FAILURE_CODES.has(code)) return true;
  if (/^general system error/i.test(msg)) return true;
  if (/\b9012\b|\b999\b/.test(combined)) return true;
  return (
    /hayajatumika|malipo hayajatumika|hayajaweza kutumika|not sent|could not send|push failed|failed to send/i.test(
      combined,
    ) || /no response from upstream|upstream system|ongoing ussd/i.test(combined)
  );
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
  const candidates = sonicPhoneCandidatesForApi(args.localPhone);
  let last: { response: Response; data: Record<string, unknown> } = {
    response: new Response(null, { status: 500 }),
    data: { status: 'error', message: 'Failed to start SonicPesa payment' },
  };

  for (const phoneForApi of candidates) {
    const payload = {
      buyer_email: args.buyerEmail,
      buyer_name: args.buyerName,
      buyer_phone: phoneForApi,
      amount: args.amountTzs,
      currency: 'TZS',
    };
    try {
      last = await gatewayFetchJson(`${SONIC_API_BASE}/payment/create_order`, {
        method: 'POST',
        headers: getSonicPesaRequestHeaders(),
        body: JSON.stringify(payload),
      });
      if (isSonicInitiateSuccess(last.data, last.response)) {
        const orderId = extractSonicOrderId(last.data);
        if (!orderId) break;
        return {
          ok: true,
          orderId,
          message: String(last.data.message ?? 'Request in progress. You will receive a prompt on your phone.'),
          raw: last.data,
        };
      }

      const errorMessage = String(last.data.message ?? last.data.error ?? 'Failed to start SonicPesa payment');
      const errorCode = String(last.data.resultcode ?? last.data.code ?? '').trim();
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
      if (!isRecoverablePaymentCreateError(errorMessage, errorCode)) {
        break;
      }
    } catch (e) {
      last = {
        response: new Response(null, { status: 502 }),
        data: { status: 'error', message: e instanceof Error ? e.message : String(e) },
      };
    }
  }

  const errorMessage = String(last.data.message ?? last.data.error ?? 'Failed to start SonicPesa payment');
  const errorCode = String(last.data.resultcode ?? last.data.code ?? '').trim();
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
  let paid = SONIC_PAID_STATUSES.has(st);
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
