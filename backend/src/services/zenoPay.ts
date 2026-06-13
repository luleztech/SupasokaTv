import { env } from '../config/env';
import { HttpError } from '../middleware/errorHandler';
import {
  isPaymentRateLimitError,
  isRecoverablePaymentCreateError,
  paymentRateLimitUserMessage,
} from '../lib/paymentProviderErrors';
import {
  phoneCandidatesForPaymentApi,
  zenoWalletProviderCandidates,
} from '../lib/tzPhone';
import { assertZenoPayAllowed } from './paymentProviderSettings';

export type ZenoOrderStatusRow = {
  payment_status?: string;
  buyer_phone?: string;
  order_id?: string;
  amount?: unknown;
  metadata?: unknown;
  [key: string]: unknown;
};

export type ZenoCreateResult = {
  ok: boolean;
  orderId: string;
  message: string;
  raw: Record<string, unknown>;
  errorMessage?: string;
  errorCode?: string;
};

function zenoOrderStatusUrl(orderId: string): string {
  const b = env.zenoApiBase.replace(/\/$/, '');
  const q = encodeURIComponent(orderId);
  return `${b}/api/payments/order-status?order_id=${q}`;
}

function zenoCreateUrl(): string {
  const b = env.zenoApiBase.replace(/\/$/, '');
  return `${b}/api/payments/mobile_money_tanzania`;
}

function isZenoCreateSuccess(j: Record<string, unknown>, httpOk: boolean): boolean {
  const status = String(j.status ?? '').toLowerCase().trim();
  if (status === 'error' || status === 'failed') return false;
  const rc = String(j.resultcode ?? j.result_code ?? j.code ?? '').trim();
  if (rc && !['000', '0', '200', '201'].includes(rc)) return false;
  const oid = String(j.order_id ?? j.orderId ?? '').trim();
  if (oid && (httpOk || status === 'success' || j.success === true)) return true;
  return httpOk && (status === 'success' || j.success === true || rc === '000' || rc === '0');
}

/** Route STK to the correct Tanzanian wallet (Vodacom, Tigo/Yas, Airtel, Halotel, …). */
export function applyZenoWalletProviderForPayload(
  payload: Record<string, unknown>,
  localPhone0: string,
): void {
  if (process.env.ZENO_SEND_PROVIDER === '0') return;
  const candidates = zenoWalletProviderCandidates(localPhone0);
  const provider = candidates.find((c) => c != null && c.trim().length > 0);
  if (provider) payload.provider = provider;
}

export async function tryCreateZenoOrder(args: {
  orderId: string;
  buyerEmail: string;
  buyerName: string;
  localPhone: string;
  amountTzs: number;
  metadata?: Record<string, unknown>;
}): Promise<ZenoCreateResult> {
  await assertZenoPayAllowed();
  const key = env.zenoApiKey.trim();
  if (!key) {
    return {
      ok: false,
      orderId: '',
      message: 'ZENO_API_KEY is not configured',
      raw: {},
      errorMessage: 'ZENO_API_KEY is not configured',
    };
  }

  const phones = phoneCandidatesForPaymentApi(args.localPhone);
  const providers = zenoWalletProviderCandidates(args.localPhone);
  let last: { response: Response; data: Record<string, unknown> } = {
    response: new Response(null, { status: 500 }),
    data: { status: 'error', message: 'Failed to start ZenoPay payment' },
  };

  for (const phoneForApi of phones) {
    for (const provider of providers) {
      const requestBody: Record<string, unknown> = {
        order_id: args.orderId,
        buyer_email: args.buyerEmail,
        buyer_name: args.buyerName,
        buyer_phone: phoneForApi,
        amount: args.amountTzs,
        metadata: args.metadata ?? {},
      };
      if (provider) {
        requestBody.provider = provider;
      }
      if (env.zenoWebhookUrl.trim()) {
        requestBody.webhook_url = env.zenoWebhookUrl.trim();
      }

      try {
        const res = await fetch(zenoCreateUrl(), {
          method: 'POST',
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
            'x-api-key': key,
          },
          body: JSON.stringify(requestBody),
        });
        const text = await res.text();
        let data: Record<string, unknown> = {};
        try {
          data = (JSON.parse(text) as Record<string, unknown>) ?? {};
        } catch {
          data = { status: 'error', message: text.slice(0, 200) };
        }

        if (isZenoCreateSuccess(data, res.ok)) {
          const pollId = String(data.order_id ?? data.orderId ?? args.orderId).trim() || args.orderId;
          return {
            ok: true,
            orderId: pollId,
            message: String(
              data.message ?? 'Request in progress. You will receive a prompt on your phone.',
            ),
            raw: data,
          };
        }

        const errorMessage = String(data.message ?? data.error ?? 'Failed to start ZenoPay payment');
        const errorCode = String(data.resultcode ?? data.result_code ?? data.code ?? '').trim();
        last = { response: res, data };

        if (isPaymentRateLimitError(errorMessage, errorCode)) {
          return {
            ok: false,
            orderId: '',
            message: paymentRateLimitUserMessage(),
            raw: data,
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
          data: {
            status: 'error',
            message: e instanceof Error ? e.message : String(e),
          },
        };
      }
    }
  }

  const errorMessage = String(last.data.message ?? last.data.error ?? 'Failed to start ZenoPay payment');
  const errorCode = String(last.data.resultcode ?? last.data.result_code ?? last.data.code ?? '').trim();
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

export async function createZenoOrder(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  await assertZenoPayAllowed();
  const key = env.zenoApiKey.trim();
  if (!key) {
    throw new HttpError(500, 'ZENO_API_KEY is not configured', 'ZENO_KEY_MISSING');
  }
  const requestBody: Record<string, unknown> = { ...body };
  const phone = String(requestBody.buyer_phone ?? '').trim();
  if (phone) applyZenoWalletProviderForPayload(requestBody, phone);
  if (
    (requestBody.webhook_url == null || String(requestBody.webhook_url).trim().length === 0) &&
    env.zenoWebhookUrl.trim()
  ) {
    requestBody.webhook_url = env.zenoWebhookUrl.trim();
  }

  const res = await fetch(zenoCreateUrl(), {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'x-api-key': key,
    },
    body: JSON.stringify(requestBody),
  });
  const text = await res.text();
  let j: unknown;
  try {
    j = JSON.parse(text);
  } catch {
    throw new HttpError(502, 'Invalid Zeno response', 'ZENO_BAD_JSON');
  }
  return (j ?? {}) as Record<string, unknown>;
}

export async function fetchZenoOrderStatus(orderId: string): Promise<ZenoOrderStatusRow | null> {
  await assertZenoPayAllowed();
  const key = env.zenoApiKey.trim();
  if (!key) {
    throw new HttpError(500, 'ZENO_API_KEY is not configured', 'ZENO_KEY_MISSING');
  }
  const trimmed = String(orderId ?? '').trim();
  if (!trimmed) return null;

  const res = await fetch(zenoOrderStatusUrl(trimmed), {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      'x-api-key': key,
    },
  });

  const text = await res.text();
  let j: unknown;
  try {
    j = JSON.parse(text);
  } catch {
    throw new HttpError(502, 'Invalid Zeno response', 'ZENO_BAD_JSON');
  }

  const pickRow = (src: unknown): ZenoOrderStatusRow | null => {
    if (!src) return null;
    if (Array.isArray(src)) {
      if (src.length === 0) return null;
      const first = src[0];
      if (!first || typeof first !== 'object') return null;
      return first as ZenoOrderStatusRow;
    }
    if (typeof src === 'object') {
      return src as ZenoOrderStatusRow;
    }
    return null;
  };

  const root = j as Record<string, unknown>;
  const fromData = pickRow(root?.data);
  if (fromData) return fromData;
  const fromOrder = pickRow(root?.order);
  if (fromOrder) return fromOrder;
  const fromTx = pickRow(root?.transaction);
  if (fromTx) return fromTx;

  if (j && typeof j === 'object') {
    const top = j as Record<string, unknown>;
    const hasTopStatus =
      top.payment_status != null ||
      top.PaymentStatus != null ||
      top.paymentStatus != null ||
      top.transaction_status != null ||
      top.TransactionStatus != null ||
      top.order_status != null ||
      top.OrderStatus != null ||
      top.payment_state != null ||
      top.PaymentState != null ||
      top.status != null;
    if (hasTopStatus) return top as ZenoOrderStatusRow;
  }
  return null;
}
