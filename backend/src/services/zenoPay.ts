import { env } from '../config/env';
import { HttpError } from '../middleware/errorHandler';
import { assertZenoPayAllowed } from './paymentProviderSettings';

export type ZenoOrderStatusRow = {
  payment_status?: string;
  buyer_phone?: string;
  order_id?: string;
  amount?: unknown;
  metadata?: unknown;
  [key: string]: unknown;
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

/** Route STK to the correct Tanzanian wallet (Vodacom, Tigo, Airtel, Halotel, Yas). */
export function applyZenoWalletProviderForPayload(
  payload: Record<string, unknown>,
  localPhone0: string,
): void {
  if (process.env.ZENO_SEND_PROVIDER === '0') return;
  const p = String(localPhone0 || '');
  if (p.startsWith('061') || p.startsWith('062') || p.startsWith('063')) {
    const v = process.env.ZENO_HALOTEL_WALLET_PROVIDER;
    payload.provider = typeof v === 'string' && v.trim() ? v.trim() : 'HALOPESA';
    return;
  }
  if (p.startsWith('074') || p.startsWith('075') || p.startsWith('076') || p.startsWith('079')) {
    if (process.env.ZENO_VODACOM_SEND_PROVIDER !== '0') {
      const v = process.env.ZENO_VODACOM_WALLET_PROVIDER;
      payload.provider = typeof v === 'string' && v.trim() ? v.trim() : 'M-PESA';
    }
    return;
  }
  if (p.startsWith('065') || p.startsWith('067') || p.startsWith('071') || p.startsWith('077')) {
    const v = process.env.ZENO_TIGO_WALLET_PROVIDER;
    payload.provider = typeof v === 'string' && v.trim() ? v.trim() : 'TIGOPESA';
    return;
  }
  if (p.startsWith('068') || p.startsWith('069') || p.startsWith('078')) {
    const v = process.env.ZENO_AIRTEL_WALLET_PROVIDER;
    payload.provider = typeof v === 'string' && v.trim() ? v.trim() : 'AIRTEL MONEY';
  }
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
  let j: any;
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
  let j: any;
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

  // Zeno payloads can vary by environment/version: prefer concrete row when present.
  const fromData = pickRow(j?.data);
  if (fromData) return fromData;
  const fromOrder = pickRow(j?.order);
  if (fromOrder) return fromOrder;
  const fromTx = pickRow(j?.transaction);
  if (fromTx) return fromTx;

  // Fallback for providers that return status fields at top-level.
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

