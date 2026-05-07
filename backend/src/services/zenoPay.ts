import { env } from '../config/env';
import { HttpError } from '../middleware/errorHandler';

export type ZenoOrderStatusRow = {
  payment_status?: string;
  buyer_phone?: string;
  order_id?: string;
  amount?: unknown;
  metadata?: unknown;
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

export async function createZenoOrder(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const key = env.zenoApiKey.trim();
  if (!key) {
    throw new HttpError(500, 'ZENO_API_KEY is not configured', 'ZENO_KEY_MISSING');
  }
  const res = await fetch(zenoCreateUrl(), {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
      'x-api-key': key,
    },
    body: JSON.stringify(body),
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

  const rc = String(j?.resultcode ?? '');
  if (rc !== '000' && rc !== '0') {
    return null;
  }
  const data = j?.data;
  if (!Array.isArray(data) || data.length === 0) return null;
  const row = data[0];
  if (!row || typeof row !== 'object') return null;
  return row as ZenoOrderStatusRow;
}

