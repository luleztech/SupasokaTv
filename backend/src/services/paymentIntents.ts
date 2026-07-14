import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';

export type PaymentIntentStatus =
  | 'PENDING'
  | 'COMPLETED'
  | 'FAILED'
  | 'CANCELLED'
  | 'EXPIRED'
  | 'REJECTED'
  | 'ERROR';

export type PaymentIntentRow = {
  order_id: string;
  public_id: string | null;
  plan_id: string | null;
  amount_tzs: number | null;
  buyer_phone: string | null;
  payment_provider: string | null;
  status: PaymentIntentStatus;
  provider_status: string | null;
  activated_at_ms: string | null;
  provider_payload: unknown;
};

function normalizeStatus(raw: string): PaymentIntentStatus {
  const s = String(raw ?? '')
    .trim()
    .toUpperCase();
  if (!s) return 'PENDING';
  // Keep in sync with isPaymentCompletedStatus / Sonic SUCCESS synonyms.
  if (
    s === 'COMPLETED' ||
    s === 'COMPLETE' ||
    s === 'PAID' ||
    s === 'SETTLED' ||
    s === 'SUCCESS' ||
    s === 'SUCCESSFUL' ||
    s === 'SUCCEEDED' ||
    s === 'APPROVED' ||
    s === 'AUTHORIZED' ||
    s === 'AUTHORISED' ||
    s === 'CONFIRMED' ||
    s === 'OK' ||
    s === 'TRUE' ||
    s === '1'
  ) {
    return 'COMPLETED';
  }
  if (s === 'FAILED' || s === 'DECLINED') return 'FAILED';
  if (s === 'CANCELLED' || s === 'CANCELED' || s === 'CANCEL' || s === 'USERCANCELLED') {
    return 'CANCELLED';
  }
  if (s === 'EXPIRED') return 'EXPIRED';
  if (s === 'REJECTED') return 'REJECTED';
  if (s === 'ERROR') return 'ERROR';
  if (s === 'ADMIN_DELETED' || s === 'VOIDED') return 'CANCELLED';
  return 'PENDING';
}

export async function ensurePaymentIntentsTable(): Promise<void> {
  const pool = getPool();
  if (!pool) return;
  await pool.query(
    `CREATE TABLE IF NOT EXISTS payment_intents (
      order_id TEXT PRIMARY KEY,
      public_id TEXT,
      plan_id TEXT,
      amount_tzs BIGINT,
      buyer_phone TEXT,
      status TEXT NOT NULL DEFAULT 'PENDING',
      provider_status TEXT,
      activated_at_ms BIGINT,
      provider_payload JSONB,
      payment_provider TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )`,
  );
  await pool.query(`ALTER TABLE payment_intents ADD COLUMN IF NOT EXISTS payment_provider TEXT`);
}

export async function upsertPendingIntent(args: {
  orderId: string;
  publicId?: string;
  planId?: string;
  amountTzs?: number;
  buyerPhone?: string;
  provider?: string;
  providerPayload?: unknown;
}): Promise<void> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(
      503,
      'DATABASE_URL is not configured — cannot track payment for premium activation',
      'NO_DATABASE',
    );
  }
  await ensurePaymentIntentsTable();
  const amount = Number.isFinite(args.amountTzs as number) ? Math.trunc(args.amountTzs as number) : null;
  await pool.query(
    `INSERT INTO payment_intents
      (order_id, public_id, plan_id, amount_tzs, buyer_phone, payment_provider, status, provider_status, provider_payload, updated_at)
     VALUES ($1, NULLIF($2, ''), NULLIF($3, ''), $4, NULLIF($5, ''), NULLIF($6, ''), 'PENDING', 'PENDING', $7::jsonb, now())
     ON CONFLICT (order_id) DO UPDATE SET
      public_id = COALESCE(NULLIF(EXCLUDED.public_id, ''), payment_intents.public_id),
      plan_id = COALESCE(NULLIF(EXCLUDED.plan_id, ''), payment_intents.plan_id),
      amount_tzs = COALESCE(EXCLUDED.amount_tzs, payment_intents.amount_tzs),
      buyer_phone = COALESCE(NULLIF(EXCLUDED.buyer_phone, ''), payment_intents.buyer_phone),
      payment_provider = CASE
        WHEN NULLIF(EXCLUDED.payment_provider, '') IS NOT NULL THEN EXCLUDED.payment_provider
        ELSE payment_intents.payment_provider
      END,
      provider_payload = COALESCE(EXCLUDED.provider_payload, payment_intents.provider_payload),
      updated_at = now()`,
    [
      args.orderId,
      args.publicId ?? '',
      args.planId ?? '',
      amount,
      args.buyerPhone ?? '',
      args.provider ?? '',
      args.providerPayload != null ? JSON.stringify(args.providerPayload) : null,
    ],
  );
}

export async function updateIntentStatus(args: {
  orderId: string;
  providerStatus: string;
  providerPayload?: unknown;
}): Promise<void> {
  const pool = getPool();
  if (!pool) return;
  await ensurePaymentIntentsTable();
  const providerStatus = String(args.providerStatus ?? '').trim().toUpperCase();
  const status = normalizeStatus(providerStatus);
  await pool.query(
    `UPDATE payment_intents
     SET status = $2,
         provider_status = $3,
         provider_payload = COALESCE($4::jsonb, provider_payload),
         updated_at = now()
     WHERE order_id = $1`,
    [args.orderId, status, providerStatus || null, args.providerPayload != null ? JSON.stringify(args.providerPayload) : null],
  );
}

export async function markIntentActivated(orderId: string): Promise<void> {
  const pool = getPool();
  if (!pool) return;
  await ensurePaymentIntentsTable();
  await pool.query(
    `UPDATE payment_intents
     SET status = 'COMPLETED',
         activated_at_ms = COALESCE(activated_at_ms, $2),
         updated_at = now()
     WHERE order_id = $1`,
    [orderId, Date.now()],
  );
}

export async function getIntent(orderId: string): Promise<PaymentIntentRow | null> {
  const pool = getPool();
  if (!pool) return null;
  await ensurePaymentIntentsTable();
  const res = await pool.query<PaymentIntentRow>(
    `SELECT order_id, public_id, plan_id, amount_tzs, buyer_phone, payment_provider, status, provider_status, activated_at_ms, provider_payload
     FROM payment_intents
     WHERE order_id = $1
     LIMIT 1`,
    [orderId],
  );
  return res.rows[0] ?? null;
}

