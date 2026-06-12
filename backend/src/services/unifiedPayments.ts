import { randomUUID } from 'crypto';
import { createZenoOrder, fetchZenoOrderStatus } from './zenoPay';
import {
  fetchSonicOrderStatus,
  isSonicPaymentCompleted,
  isSonicRawPaymentCompleted,
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
import { normalizePhoneToLocal0 } from '../lib/tzPhone';

export { normalizePhoneToLocal0 } from '../lib/tzPhone';

export function paymentStatusFromZenoRow(row: Record<string, unknown> | null | undefined): string {
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
  if (row.success === true) return 'COMPLETED';
  const rc = String(row.resultcode ?? row.result_code ?? row.code ?? '').trim();
  if (rc === '000' || rc === '0') return 'COMPLETED';
  return '';
}

export function isPaymentCompletedStatus(ps: string): boolean {
  const s = String(ps ?? '').trim().toUpperCase();
  if (!s) return false;
  if (isSonicPaymentCompleted(s)) return true;
  return (
    s === 'COMPLETED' || s === 'COMPLETE' || s === 'SUCCESS' || s === 'SUCCESSFUL' ||
    s === 'SUCCEEDED' || s === 'PAID' || s === 'APPROVED' || s === 'AUTHORIZED' ||
    s === 'AUTHORISED' || s === 'SETTLED' || s === 'CONFIRMED'
  );
}

function isPaymentTerminalFailure(ps: string): boolean {
  const s = String(ps ?? '').trim().toUpperCase();
  return (
    s === 'FAILED' || s === 'ERROR' || s === 'CANCELLED' || s === 'CANCELED' ||
    s === 'REJECTED' || s === 'DECLINED' || s === 'EXPIRED'
  );
}

function normalizeStoredProvider(raw: string | null | undefined): PaymentProviderId | null {
  if (typeof raw !== 'string' || !raw.trim()) return null;
  const compact = raw.toLowerCase().trim().replace(/[^a-z0-9]/g, '');
  if (compact === 'sonicpesa') return PAYMENT_PROVIDERS.SONICPESA;
  if (compact === 'zeno' || compact === 'zenopay') return PAYMENT_PROVIDERS.ZENO;
  return null;
}

async function resolveGatewayForOrder(orderId: string): Promise<PaymentProviderId> {
  const selected = await getSelectedPaymentProvider();
  // Admin toggle is authoritative: when SonicPesa is active, never call Zeno for status/confirm.
  if (selected === PAYMENT_PROVIDERS.SONICPESA) {
    return PAYMENT_PROVIDERS.SONICPESA;
  }
  const intent = await getIntent(orderId);
  const fromIntent = normalizeStoredProvider(intent?.payment_provider);
  if (fromIntent) return fromIntent;
  return selected;
}

function metadataFromProviderPayload(payload: unknown): { publicId: string; planId: string } {
  if (!payload || typeof payload !== 'object') return { publicId: '', planId: '' };
  const p = payload as Record<string, unknown>;
  const meta =
    p.metadata && typeof p.metadata === 'object' && !Array.isArray(p.metadata)
      ? (p.metadata as Record<string, unknown>)
      : {};
  const publicId = String(
    meta.external_id ?? meta.public_id ?? p.public_id ?? p.publicId ?? '',
  ).trim();
  const planId = String(meta.plan_id ?? p.plan_id ?? p.planId ?? '').trim();
  return { publicId, planId };
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

/** Map legacy Zeno-shaped POST bodies to unified checkout fields. */
export function parseStartPaymentFromLegacyBody(
  body: Record<string, unknown>,
): StartPaymentInput | null {
  const metadata = (body.metadata ?? {}) as Record<string, unknown>;
  const publicId = String(
    body.publicId ??
      body.externalId ??
      metadata.external_id ??
      metadata.public_id ??
      '',
  ).trim();
  const planId = String(body.planId ?? body.bundle ?? metadata.plan_id ?? '').trim();
  const phone = String(
    body.phone ?? body.buyer_phone ?? metadata.buyer_phone ?? '',
  ).trim();
  const amountTzs = Number(body.amount ?? body.amountTzs ?? 0);
  const orderId = String(body.order_id ?? body.orderId ?? '').trim();

  if (!publicId || !planId || !phone || amountTzs < 1) {
    return null;
  }

  return {
    orderId: orderId || undefined,
    publicId,
    planId,
    amountTzs,
    phone,
    buyerName: String(body.buyer_name ?? body.buyerName ?? publicId).trim(),
    buyerEmail: String(body.buyer_email ?? body.buyerEmail ?? `${publicId}@supasoka.app`).trim(),
  };
}

export function startPaymentSuccessJson(out: {
  orderId: string;
  message: string;
  provider: PaymentProviderId;
}) {
  return {
    ok: true,
    status: 'success',
    resultcode: '000',
    order_id: out.orderId,
    orderId: out.orderId,
    message: out.message,
    provider: out.provider,
    paymentProvider: out.provider,
  };
}

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

async function resolvePaidStatusForOrder(
  orderId: string,
  gateway: PaymentProviderId,
): Promise<string> {
  if (gateway === PAYMENT_PROVIDERS.SONICPESA) {
    const { paymentStatus, raw } = await fetchSonicOrderStatus(orderId);
    if (isPaymentCompletedStatus(paymentStatus) || isSonicRawPaymentCompleted(raw)) {
      return paymentStatus || 'COMPLETED';
    }
    return paymentStatus;
  }
  const row = await fetchZenoOrderStatus(orderId);
  return paymentStatusFromZenoRow(row as Record<string, unknown> | null);
}

type ActivateOverrides = {
  publicId?: string;
  planId?: string;
  phone?: string;
};

function isPremiumUntilActive(until: number | null | undefined): until is number {
  return until != null && Number.isFinite(until) && until > Date.now();
}

function resolveOrderIdentity(
  orderId: string,
  intent: Awaited<ReturnType<typeof getIntent>>,
  overrides?: ActivateOverrides,
): { publicId: string; planId: string; phone: string } {
  let publicId = String(overrides?.publicId ?? intent?.public_id ?? '').trim();
  let planId = String(overrides?.planId ?? intent?.plan_id ?? '').trim();
  if (!publicId || !planId) {
    const fromPayload = metadataFromProviderPayload(intent?.provider_payload);
    publicId = publicId || fromPayload.publicId;
    planId = planId || fromPayload.planId;
  }
  const phoneNorm = normalizePhoneToLocal0(overrides?.phone ?? intent?.buyer_phone ?? '');
  const phone = phoneNorm.local ?? String(overrides?.phone ?? intent?.buyer_phone ?? '').trim();
  return { publicId, planId, phone };
}

async function writePremiumForOrder(
  orderId: string,
  gateway: PaymentProviderId,
  identity: { publicId: string; planId: string; phone: string },
): Promise<{ premiumUntilMs: number }> {
  const activated = await activatePremiumForUser({
    publicId: identity.publicId,
    planId: identity.planId,
    phone: identity.phone,
    note: `${gateway}:${orderId}`,
  });
  await markIntentActivated(orderId);
  logger.info(
    { orderId, publicId: identity.publicId, planId: identity.planId, premiumUntilMs: activated.premiumUntilMs },
    'payment_activated_premium',
  );
  return { premiumUntilMs: activated.premiumUntilMs };
}

/** Idempotent: activate premium when provider reports paid (poll / webhook / confirm). */
export async function activatePremiumIfCompletedOrder(
  orderId: string,
  overrides?: ActivateOverrides,
): Promise<{ activated: boolean; premiumUntilMs?: number }> {
  const intent = await getIntent(orderId);
  const identity = resolveOrderIdentity(orderId, intent, overrides);
  if (!identity.publicId || !identity.planId) {
    logger.warn({ orderId }, 'payment_activate_missing_metadata');
    return { activated: false };
  }
  if (intent?.activated_at_ms != null) {
    const { getUserPremiumStatus } = await import('./userDirectory');
    const until = await getUserPremiumStatus(identity.publicId);
    if (isPremiumUntilActive(until)) {
      return { activated: true, premiumUntilMs: until };
    }
    // Intent marked paid but premium missing/expired — re-grant below when provider confirms paid.
  }

  const gateway = await resolveGatewayForOrder(orderId);
  const ps = await resolvePaidStatusForOrder(orderId, gateway);
  if (!isPaymentCompletedStatus(ps)) {
    return { activated: false };
  }

  const out = await writePremiumForOrder(orderId, gateway, identity);
  return { activated: true, premiumUntilMs: out.premiumUntilMs };
}

/**
 * Provider already confirmed paid — always persist premium when we know user + plan
 * (covers DB races, webhook/poll timing, or a failed first activation attempt).
 */
export async function ensurePremiumActivatedForPaidOrder(
  orderId: string,
  overrides?: ActivateOverrides,
): Promise<{ activated: boolean; premiumUntilMs?: number }> {
  const trimmed = orderId.trim();
  if (!trimmed) return { activated: false };

  const intent = await getIntent(trimmed);
  const identity = resolveOrderIdentity(trimmed, intent, overrides);
  if (!identity.publicId || !identity.planId) {
    logger.warn({ orderId: trimmed }, 'payment_force_activate_missing_metadata');
    return { activated: false };
  }

  const { getUserPremiumStatus } = await import('./userDirectory');
  const existingUntil = await getUserPremiumStatus(identity.publicId);
  if (isPremiumUntilActive(existingUntil)) {
    return { activated: true, premiumUntilMs: existingUntil };
  }

  const act = await activatePremiumIfCompletedOrder(trimmed, overrides);
  if (act.activated && isPremiumUntilActive(act.premiumUntilMs)) return act;

  try {
    const gateway = await resolveGatewayForOrder(trimmed);
    if (intent?.activated_at_ms != null) {
      const out = await writePremiumForOrder(trimmed, gateway, identity);
      return { activated: true, premiumUntilMs: out.premiumUntilMs };
    }
    const ps = await resolvePaidStatusForOrder(trimmed, gateway);
    if (!isPaymentCompletedStatus(ps)) {
      return { activated: false };
    }
    const out = await writePremiumForOrder(trimmed, gateway, identity);
    return { activated: true, premiumUntilMs: out.premiumUntilMs };
  } catch (e) {
    logger.error({ orderId: trimmed, err: e }, 'payment_force_activate_failed');
    return { activated: false };
  }
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
    const act = await ensurePremiumActivatedForPaidOrder(trimmed, {
      publicId: local?.public_id ?? undefined,
      planId: local?.plan_id ?? undefined,
    });
    return {
      status: 'COMPLETED',
      resultcode: '000',
      raw: { data: [{ payment_status: 'COMPLETED', order_id: trimmed }] },
      activated: act.activated,
      premiumUntilMs: act.premiumUntilMs,
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
    if (isSonicPaymentCompleted(paymentStatus) || isSonicRawPaymentCompleted(raw)) {
      const act = await ensurePremiumActivatedForPaidOrder(trimmed);
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
    const act = await ensurePremiumActivatedForPaidOrder(trimmed);
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

  let tracked = await getIntent(orderId);
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
    if (isPremiumUntilActive(until)) {
      return { premiumUntilMs: until };
    }
    const gateway = await resolveGatewayForOrder(orderId);
    const out = await writePremiumForOrder(orderId, gateway, { publicId, planId, phone });
    return { premiumUntilMs: out.premiumUntilMs };
  }

  const gateway = await resolveGatewayForOrder(orderId);
  if (!tracked?.public_id || !tracked.plan_id) {
    await upsertPendingIntent({
      orderId,
      publicId,
      planId,
      buyerPhone: phone,
      provider: gateway,
    });
    tracked = await getIntent(orderId);
  }

  const ps = await resolvePaidStatusForOrder(orderId, gateway);

  if (ps) {
    await updateIntentStatus({ orderId, providerStatus: ps });
  }

  if (!isPaymentCompletedStatus(ps)) {
    const code = isPaymentTerminalFailure(ps) ? 409 : 402;
    throw new HttpError(code, 'Payment not completed', 'NOT_COMPLETED');
  }

  const act = await ensurePremiumActivatedForPaidOrder(orderId, { publicId, planId, phone });
  if (!act.activated || act.premiumUntilMs == null) {
    throw new HttpError(500, 'Payment completed but premium could not be activated', 'ACTIVATE_FAILED');
  }
  return { premiumUntilMs: act.premiumUntilMs };
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
