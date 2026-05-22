import { randomUUID } from 'crypto';
import { createZenoOrder, fetchZenoOrderStatus } from './zenoPay';
import {
  fetchSonicOrderStatus,
  isSonicPaymentCompleted,
  tryCreateSonicOrder,
} from './sonicPesa';
import { logger } from '../lib/logger';
import {
  getSelectedPaymentProvider,
  isProviderConfigured,
  isSonicPesaConfigured,
  isZenoConfigured,
  PAYMENT_PROVIDERS,
  type PaymentProviderId,
} from './paymentProviderSettings';
import {
  getIntent,
  markIntentActivated,
  upsertPendingIntent,
  updateIntentStatus,
} from './paymentIntents';
import { activatePremiumForUser } from './premiumActivation';
import { HttpError } from '../middleware/errorHandler';
import { env } from '../config/env';

const TZ_PREFIXES = [
  '061', '062', '063', '065', '067', '068', '069',
  '071', '074', '075', '076', '077', '078', '079',
];

export function normalizePhoneToLocal0(rawPhone: string): { local?: string; error?: string } {
  let normalizedPhone = String(rawPhone ?? '').replace(/\s+/g, '');
  if (normalizedPhone.startsWith('+') && !normalizedPhone.startsWith('+255')) {
    return {
      error:
        'Malipo yanatumwa kwa nambari za simu za Tanzania pekee. Tumia muundo wa ndani unaoanza na 0 (mfano 0712345678).',
    };
  }
  if (normalizedPhone.startsWith('00') && !normalizedPhone.startsWith('00255')) {
    return {
      error:
        'Malipo yanatumwa kwa nambari za simu za Tanzania pekee. Tumia muundo wa ndani unaoanza na 0 (mfano 0712345678).',
    };
  }
  if (normalizedPhone.startsWith('+255')) {
    normalizedPhone = `0${normalizedPhone.slice(4)}`;
  } else if (normalizedPhone.startsWith('00255')) {
    normalizedPhone = `0${normalizedPhone.slice(5)}`;
  } else if (normalizedPhone.startsWith('255') && normalizedPhone.length >= 12) {
    normalizedPhone = `0${normalizedPhone.slice(3)}`;
  }
  if (/^[1-9]\d{8}$/.test(normalizedPhone)) {
    normalizedPhone = `0${normalizedPhone}`;
  }
  if (!/^\d+$/.test(normalizedPhone)) {
    return {
      error: 'Nambari ya simu lazima iwe nambari ya Tanzania tu: anza kwa 0 (mfano 0712345678).',
    };
  }
  const isValidFormat = /^0[0-9]{8,9}$/.test(normalizedPhone);
  const hasValidPrefix = TZ_PREFIXES.some((p) => normalizedPhone.startsWith(p));
  if (!isValidFormat || !hasValidPrefix) {
    return {
      error:
        'Invalid Tanzanian phone number. Use format: 061–063 (Halotel), 065/071 (Yas), 067/077 (Tigo), 068–069/078 (Airtel), 074–076/079 (Vodacom).',
    };
  }
  return { local: normalizedPhone };
}

function paymentStatusFromZenoRow(row: Record<string, unknown> | null | undefined): string {
  if (!row || typeof row !== 'object') return '';
  const keys = [
    'payment_status', 'PaymentStatus', 'paymentStatus',
    'transaction_status', 'TransactionStatus', 'order_status', 'OrderStatus',
    'payment_state', 'PaymentState', 'status',
  ] as const;
  for (const k of keys) {
    const v = row[k];
    if (v == null) continue;
    const s = String(v).trim();
    if (s.length > 0) return s.toUpperCase();
  }
  return '';
}

export function isPaymentCompletedStatus(ps: string): boolean {
  const s = String(ps ?? '').trim().toUpperCase();
  return (
    s === 'COMPLETED' || s === 'COMPLETE' || s === 'SUCCESS' || s === 'SUCCESSFUL' ||
    s === 'SUCCEEDED' || s === 'PAID' || s === 'APPROVED' || s === 'AUTHORIZED' ||
    s === 'AUTHORISED' || s === 'SETTLED'
  );
}

function isPaymentTerminalFailure(ps: string): boolean {
  const s = String(ps ?? '').trim().toUpperCase();
  return (
    s === 'FAILED' || s === 'ERROR' || s === 'CANCELLED' || s === 'CANCELED' ||
    s === 'REJECTED' || s === 'DECLINED' || s === 'EXPIRED'
  );
}

async function resolveGatewayForOrder(orderId: string): Promise<PaymentProviderId> {
  const intent = await getIntent(orderId);
  const raw = (intent as { payment_provider?: string } | null)?.payment_provider;
  if (typeof raw === 'string' && raw.trim()) {
    const compact = raw.toLowerCase().trim().replace(/[^a-z0-9]/g, '');
    if (compact === 'sonicpesa') return PAYMENT_PROVIDERS.SONICPESA;
    if (compact === 'zeno' || compact === 'zenopay') return PAYMENT_PROVIDERS.ZENO;
  }
  return getSelectedPaymentProvider();
}

export type StartPaymentInput = {
  orderId?: string;
  publicId: string;
  planId: string;
  amountTzs: number;
  phone: string;
  buyerName?: string;
  buyerEmail?: string;
};

export async function startUnifiedPayment(input: StartPaymentInput): Promise<{
  orderId: string;
  message: string;
  provider: PaymentProviderId;
  status: string;
}> {
  const phoneNorm = normalizePhoneToLocal0(input.phone);
  if (phoneNorm.error || !phoneNorm.local) {
    throw new HttpError(400, phoneNorm.error ?? 'Invalid phone', 'BAD_PHONE');
  }
  const localPhone = phoneNorm.local;
  const amountTzs = Math.trunc(input.amountTzs);
  if (amountTzs < 1) {
    throw new HttpError(400, 'Amount must be at least 1 TZS', 'BAD_AMOUNT');
  }

  const selected = await getSelectedPaymentProvider();

  if (!isProviderConfigured(selected)) {
    if (selected === PAYMENT_PROVIDERS.SONICPESA) {
      throw new HttpError(
        503,
        'SonicPesa haijasanidi kwenye seva. Wasiliana na admin au chagua ZenoPay kwenye SupaAdmin.',
        'SONIC_NOT_CONFIGURED',
      );
    }
    throw new HttpError(
      503,
      'ZenoPay haijasanidi kwenye seva. Wasiliana na admin au chagua SonicPesa kwenye SupaAdmin.',
      'ZENO_NOT_CONFIGURED',
    );
  }

  const buyerName = (input.buyerName ?? input.publicId).trim() || 'Mteja';
  const buyerEmail = (input.buyerEmail ?? `${input.publicId}@supasoka.app`).trim();

  if (selected === PAYMENT_PROVIDERS.SONICPESA) {
    const sonic = await tryCreateSonicOrder({
      buyerEmail,
      buyerName,
      localPhone,
      amountTzs,
    });
    if (!sonic.ok || !sonic.orderId) {
      throw new HttpError(
        400,
        sonic.errorMessage ?? sonic.message ?? 'Failed to start SonicPesa payment',
        'SONIC_CREATE_FAILED',
      );
    }
    await upsertPendingIntent({
      orderId: sonic.orderId,
      publicId: input.publicId,
      planId: input.planId,
      amountTzs,
      buyerPhone: localPhone,
      provider: PAYMENT_PROVIDERS.SONICPESA,
      providerPayload: sonic.raw,
    });
    return {
      orderId: sonic.orderId,
      message: sonic.message,
      provider: PAYMENT_PROVIDERS.SONICPESA,
      status: 'pending',
    };
  }

  const orderId = (input.orderId ?? randomUUID()).trim();
  const zenoBody: Record<string, unknown> = {
    order_id: orderId,
    buyer_email: buyerEmail,
    buyer_name: buyerName,
    buyer_phone: localPhone,
    amount: amountTzs,
    metadata: {
      plan_id: input.planId,
      external_id: input.publicId,
      public_id: input.publicId,
      buyer_phone: localPhone,
    },
  };
  if (env.zenoWebhookUrl.trim()) {
    zenoBody.webhook_url = env.zenoWebhookUrl.trim();
  }

  const out = await createZenoOrder(zenoBody);
  const pollId = String(out.order_id ?? out.orderId ?? orderId).trim() || orderId;

  await upsertPendingIntent({
    orderId: pollId,
    publicId: input.publicId,
    planId: input.planId,
    amountTzs,
    buyerPhone: localPhone,
    provider: PAYMENT_PROVIDERS.ZENO,
    providerPayload: out,
  });

  const msg = String(out.message ?? 'Request in progress. You will receive a prompt on your phone.');
  return {
    orderId: pollId,
    message: msg,
    provider: PAYMENT_PROVIDERS.ZENO,
    status: 'pending',
  };
}

/** Idempotent: activate premium when provider reports paid (poll / webhook / confirm). */
export async function activatePremiumIfCompletedOrder(
  orderId: string,
): Promise<{ activated: boolean; premiumUntilMs?: number }> {
  const intent = await getIntent(orderId);
  if (!intent?.public_id || !intent.plan_id) {
    return { activated: false };
  }
  if (intent.activated_at_ms != null) {
    const { getUserPremiumStatus } = await import('./userDirectory');
    const until = await getUserPremiumStatus(intent.public_id);
    return { activated: true, premiumUntilMs: until ?? undefined };
  }

  const gateway = await resolveGatewayForOrder(orderId);
  let ps = '';
  if (gateway === PAYMENT_PROVIDERS.SONICPESA) {
    const { paymentStatus } = await fetchSonicOrderStatus(orderId);
    ps = paymentStatus;
  } else {
    const row = await fetchZenoOrderStatus(orderId);
    ps = paymentStatusFromZenoRow(row as Record<string, unknown> | null);
  }
  if (!isPaymentCompletedStatus(ps)) {
    return { activated: false };
  }

  const phoneNorm = normalizePhoneToLocal0(intent.buyer_phone ?? '');
  const activated = await activatePremiumForUser({
    publicId: intent.public_id,
    planId: intent.plan_id,
    phone: phoneNorm.local ?? intent.buyer_phone ?? '',
    note: `${gateway}:${orderId}`,
  });
  await markIntentActivated(orderId);
  logger.info(
    { orderId, publicId: intent.public_id, planId: intent.plan_id, premiumUntilMs: activated.premiumUntilMs },
    'payment_poll_activated_premium',
  );
  return { activated: true, premiumUntilMs: activated.premiumUntilMs };
}

export async function pollUnifiedPaymentStatus(orderId: string): Promise<{
  status: string;
  raw?: unknown;
  resultcode?: string;
  premiumUntilMs?: number;
  activated?: boolean;
}> {
  const trimmed = orderId.trim();
  if (!trimmed) {
    throw new HttpError(400, 'order_id is required', 'MISSING_ORDER_ID');
  }

  const local = await getIntent(trimmed);
  if (local?.activated_at_ms != null || local?.status === 'COMPLETED') {
    const { getUserPremiumStatus } = await import('./userDirectory');
    const until = local.public_id ? await getUserPremiumStatus(local.public_id) : null;
    return {
      status: 'COMPLETED',
      resultcode: '000',
      raw: { data: [{ payment_status: 'COMPLETED', order_id: trimmed }] },
      activated: true,
      premiumUntilMs: until ?? undefined,
    };
  }

  const gateway = await resolveGatewayForOrder(trimmed);

  if (gateway === PAYMENT_PROVIDERS.SONICPESA) {
    const { ok, paymentStatus, raw } = await fetchSonicOrderStatus(trimmed);
    const msg = String(raw.message ?? raw.error ?? '').toLowerCase();
    if (!ok && (msg.includes('not found') || msg.includes('no order'))) {
      return { status: 'PENDING', raw };
    }
    if (paymentStatus) {
      await updateIntentStatus({
        orderId: trimmed,
        providerStatus: paymentStatus,
        providerPayload: raw,
      });
    }
    if (isSonicPaymentCompleted(paymentStatus)) {
      const act = await activatePremiumIfCompletedOrder(trimmed);
      return {
        status: 'COMPLETED',
        resultcode: '000',
        raw: { data: [{ payment_status: 'COMPLETED', order_id: trimmed }] },
        activated: act.activated,
        premiumUntilMs: act.premiumUntilMs,
      };
    }
    return { status: paymentStatus || 'PENDING', raw };
  }

  const row = await fetchZenoOrderStatus(trimmed);
  const ps = paymentStatusFromZenoRow(row as Record<string, unknown> | null);
  if (ps) {
    await updateIntentStatus({
      orderId: trimmed,
      providerStatus: ps,
      providerPayload: row ?? null,
    });
  }
  if (isPaymentCompletedStatus(ps)) {
    const act = await activatePremiumIfCompletedOrder(trimmed);
    return {
      status: 'COMPLETED',
      resultcode: '000',
      raw: row ? { data: [row] } : { data: [{ payment_status: 'COMPLETED', order_id: trimmed }] },
      activated: act.activated,
      premiumUntilMs: act.premiumUntilMs,
    };
  }
  return {
    status: ps || 'PENDING',
    resultcode: row ? '000' : '404',
    raw: row ? { data: [row] } : { data: [] },
  };
}

export async function confirmPremiumForOrder(args: {
  orderId: string;
  publicId: string;
  planId: string;
  phone?: string;
}): Promise<{ premiumUntilMs: number }> {
  const { orderId, publicId, planId } = args;
  if (!orderId || !publicId || !planId) {
    throw new HttpError(400, 'Missing orderId/publicId/planId', 'MISSING_FIELDS');
  }

  const tracked = await getIntent(orderId);
  const phoneNorm = normalizePhoneToLocal0(args.phone || tracked?.buyer_phone || '');
  const phone = phoneNorm.local ?? String(args.phone ?? tracked?.buyer_phone ?? '').trim();
  if (tracked?.public_id && tracked.public_id !== publicId) {
    throw new HttpError(409, 'Order belongs to another user', 'PUBLIC_ID_MISMATCH');
  }
  if (tracked?.plan_id && tracked.plan_id !== planId) {
    throw new HttpError(409, 'Order does not match selected plan', 'PLAN_MISMATCH');
  }
  if (tracked?.activated_at_ms != null) {
    const { getUserPremiumStatus } = await import('./userDirectory');
    const until = await getUserPremiumStatus(publicId);
    return { premiumUntilMs: until ?? Date.now() };
  }

  const gateway = await resolveGatewayForOrder(orderId);
  let ps = '';

  if (gateway === PAYMENT_PROVIDERS.SONICPESA) {
    const { paymentStatus } = await fetchSonicOrderStatus(orderId);
    ps = paymentStatus;
  } else {
    const row = await fetchZenoOrderStatus(orderId);
    ps = paymentStatusFromZenoRow(row as Record<string, unknown> | null);
  }

  if (ps) {
    await updateIntentStatus({ orderId, providerStatus: ps });
  }

  if (!isPaymentCompletedStatus(ps)) {
    const code = isPaymentTerminalFailure(ps) ? 409 : 402;
    throw new HttpError(code, 'Payment not completed', 'NOT_COMPLETED');
  }

  const activated = await activatePremiumForUser({
    publicId,
    planId,
    phone: phone || phoneNorm.local || '',
    note: `${gateway}:${orderId}`,
  });
  await markIntentActivated(orderId);
  return { premiumUntilMs: activated.premiumUntilMs };
}

export function providerHealthSnapshot(selected: PaymentProviderId): {
  paymentProvider: PaymentProviderId;
  configured: boolean;
  zenoConfigured: boolean;
  sonicConfigured: boolean;
} {
  const zenoConfigured = isZenoConfigured();
  const sonicConfigured = isSonicPesaConfigured();
  const configured = isProviderConfigured(selected);
  return { paymentProvider: selected, configured, zenoConfigured, sonicConfigured };
}
