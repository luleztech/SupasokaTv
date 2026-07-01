import {
  fetchSonicOrderStatus,
  isSonicPaymentCompleted,
  isSonicRawPaymentCompleted,
  mapSonicInitiateUserError,
  tryCreateSonicOrder,
} from './sonicPesa';
import { logger } from '../lib/logger';
import {
  getSelectedPaymentProvider,
  isProviderConfigured,
  isSonicPesaConfigured,
  PAYMENT_PROVIDERS,
  type PaymentProviderId,
} from './paymentProviderSettings';
import {
  ensurePaymentIntentsTable,
  getIntent,
  markIntentActivated,
  upsertPendingIntent,
  updateIntentStatus,
} from './paymentIntents';
import { getPool } from '../db/pool';
import { activatePremiumForUser } from './premiumActivation';
import { HttpError } from '../middleware/errorHandler';
import { normalizePhoneToLocal0 } from '../lib/tzPhone';

export { normalizePhoneToLocal0 } from '../lib/tzPhone';

export function paymentStatusFromProviderRow(row: Record<string, unknown> | null | undefined): string {
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
    s === 'USERCANCELLED' ||
    s === 'REJECTED' || s === 'DECLINED' || s === 'EXPIRED'
  );
}

export function metadataFromProviderPayload(payload: unknown): { publicId: string; planId: string } {
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

/** Map legacy checkout POST bodies to unified fields. */
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

  if (!publicId || !planId || !phone || amountTzs < 1) {
    return null;
  }

  return {
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

  await getSelectedPaymentProvider();

  if (!isProviderConfigured()) {
    throw new HttpError(
      503,
      'SonicPesa haijasanidi kwenye seva. Wasiliana na admin.',
      'SONIC_NOT_CONFIGURED',
    );
  }

  const buyerName = (input.buyerName ?? input.publicId).trim() || 'Mteja';
  const buyerEmail = (input.buyerEmail ?? `${input.publicId}@supasoka.app`).trim();

  const sonic = await tryCreateSonicOrder({
    buyerEmail,
    buyerName,
    localPhone,
    amountTzs,
  });
  if (!sonic.ok || !sonic.orderId) {
    const userMsg = mapSonicInitiateUserError(
      localPhone,
      sonic.errorMessage ?? sonic.message,
      sonic.errorCode ?? '',
    );
    throw new HttpError(400, userMsg, 'SONIC_CREATE_FAILED');
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

async function resolvePaidStatusForOrder(orderId: string): Promise<string> {
  const { paymentStatus, raw } = await fetchSonicOrderStatus(orderId);
  if (isPaymentCompletedStatus(paymentStatus) || isSonicRawPaymentCompleted(raw)) {
    return paymentStatus || 'COMPLETED';
  }
  return paymentStatus;
}

type ActivateOverrides = {
  publicId?: string;
  planId?: string;
  phone?: string;
};

function intentOverrides(
  intent: Awaited<ReturnType<typeof getIntent>> | null | undefined,
): ActivateOverrides | undefined {
  if (!intent) return undefined;
  return {
    publicId: intent.public_id ?? undefined,
    planId: intent.plan_id ?? undefined,
    phone: intent.buyer_phone ?? undefined,
  };
}

export async function reconcilePremiumForUser(publicId: string): Promise<number | null> {
  const trimmed = String(publicId ?? '').trim();
  if (!trimmed) return null;

  const { getUserPremiumStatus, isUserPremiumRevokeLocked } = await import('./userDirectory');
  if (await isUserPremiumRevokeLocked(trimmed)) return null;

  const existing = await getUserPremiumStatus(trimmed);
  if (isPremiumUntilActiveLocal(existing)) return existing;

  const pool = getPool();
  if (!pool) return null;
  await ensurePaymentIntentsTable();

  const res = await pool.query<{ order_id: string }>(
    `SELECT order_id
     FROM payment_intents
     WHERE public_id = $1
       AND updated_at > now() - interval '90 days'
       AND status NOT IN ('FAILED', 'CANCELLED', 'EXPIRED', 'REJECTED', 'ERROR')
     ORDER BY activated_at_ms NULLS FIRST, updated_at DESC
     LIMIT 10`,
    [trimmed],
  );

  for (const row of res.rows) {
    const act = await ensurePremiumActivatedForPaidOrder(row.order_id, { publicId: trimmed });
    if (act.activated && isPremiumUntilActiveLocal(act.premiumUntilMs)) {
      return act.premiumUntilMs!;
    }
  }
  return null;
}

function isPremiumUntilActiveLocal(until: number | null | undefined): until is number {
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
  identity: { publicId: string; planId: string; phone: string },
): Promise<{ premiumUntilMs: number }> {
  const activated = await activatePremiumForUser({
    publicId: identity.publicId,
    planId: identity.planId,
    phone: identity.phone,
    note: `sonicpesa:${orderId}`,
  });
  await markIntentActivated(orderId);
  logger.info(
    { orderId, publicId: identity.publicId, planId: identity.planId, premiumUntilMs: activated.premiumUntilMs },
    'payment_activated_premium',
  );
  return { premiumUntilMs: activated.premiumUntilMs };
}

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
    if (isPremiumUntilActiveLocal(until)) {
      return { activated: true, premiumUntilMs: until };
    }
    const ps = await resolvePaidStatusForOrder(orderId);
    if (!isPaymentCompletedStatus(ps)) {
      return { activated: false };
    }
    const out = await writePremiumForOrder(orderId, identity);
    return { activated: true, premiumUntilMs: out.premiumUntilMs };
  }

  const ps = await resolvePaidStatusForOrder(orderId);
  if (!isPaymentCompletedStatus(ps)) {
    return { activated: false };
  }

  const out = await writePremiumForOrder(orderId, identity);
  return { activated: true, premiumUntilMs: out.premiumUntilMs };
}

async function regrantPremiumForPaidOrder(
  orderId: string,
  identity: { publicId: string; planId: string; phone: string },
  reason: string,
): Promise<{ activated: boolean; premiumUntilMs?: number }> {
  try {
    const ps = await resolvePaidStatusForOrder(orderId);
    if (!isPaymentCompletedStatus(ps)) {
      return { activated: false };
    }
    const out = await writePremiumForOrder(orderId, identity);
    logger.info({ orderId, publicId: identity.publicId, reason }, 'payment_premium_regranted');
    return { activated: true, premiumUntilMs: out.premiumUntilMs };
  } catch (e) {
    logger.error({ orderId, err: e, reason }, 'payment_regrant_failed');
    return { activated: false };
  }
}

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

  const { getUserPremiumStatus, isUserPremiumRevokeLocked } = await import('./userDirectory');
  if (await isUserPremiumRevokeLocked(identity.publicId)) {
    return { activated: false };
  }

  const existingUntil = await getUserPremiumStatus(identity.publicId);
  if (isPremiumUntilActiveLocal(existingUntil)) {
    return { activated: true, premiumUntilMs: existingUntil };
  }

  if (intent?.activated_at_ms != null) {
    return regrantPremiumForPaidOrder(trimmed, identity, 'activated_intent_missing_premium');
  }

  const act = await activatePremiumIfCompletedOrder(trimmed, overrides);
  if (act.activated && isPremiumUntilActiveLocal(act.premiumUntilMs)) return act;

  return regrantPremiumForPaidOrder(trimmed, identity, 'force_activate');
}

export async function pollUnifiedPaymentStatus(orderId: string): Promise<{
  status: string;
  raw?: unknown;
  resultcode?: string;
  premiumUntilMs?: number;
  activated?: boolean;
  intentPublicId?: string;
  intentPlanId?: string;
}> {
  const trimmed = orderId.trim();
  if (!trimmed) {
    throw new HttpError(400, 'order_id is required', 'MISSING_ORDER_ID');
  }

  const local = await getIntent(trimmed);
  const intentMeta = {
    intentPublicId: local?.public_id ?? undefined,
    intentPlanId: local?.plan_id ?? undefined,
  };
  if (local?.activated_at_ms != null || local?.status === 'COMPLETED') {
    const ps = await resolvePaidStatusForOrder(trimmed);
    const providerPaid = isPaymentCompletedStatus(ps);
    if (!providerPaid && local?.activated_at_ms == null) {
      return {
        status: ps || local?.provider_status || 'PENDING',
        raw: local?.provider_payload ?? { data: [{ payment_status: ps || 'PENDING', order_id: trimmed }] },
        ...intentMeta,
      };
    }
    const act = await ensurePremiumActivatedForPaidOrder(trimmed, {
      publicId: local?.public_id ?? undefined,
      planId: local?.plan_id ?? undefined,
    });
    if (!providerPaid && !act.activated) {
      return {
        status: ps || 'PENDING',
        raw: local?.provider_payload ?? { data: [{ payment_status: ps || 'PENDING', order_id: trimmed }] },
        ...intentMeta,
      };
    }
    return {
      status: 'COMPLETED',
      resultcode: '000',
      raw: { data: [{ payment_status: 'COMPLETED', order_id: trimmed }] },
      activated: act.activated,
      premiumUntilMs: act.premiumUntilMs,
      ...intentMeta,
    };
  }

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
    const intentAfter = (await getIntent(trimmed)) ?? local;
    const act = await ensurePremiumActivatedForPaidOrder(trimmed, intentOverrides(intentAfter));
    return {
      status: 'COMPLETED',
      resultcode: '000',
      raw: { data: [{ payment_status: 'COMPLETED', order_id: trimmed }] },
      activated: act.activated,
      premiumUntilMs: act.premiumUntilMs,
      intentPublicId: intentAfter?.public_id ?? local?.public_id ?? undefined,
      intentPlanId: intentAfter?.plan_id ?? local?.plan_id ?? undefined,
    };
  }
  return { status: paymentStatus || 'PENDING', raw, ...intentMeta };
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
    const { getUserPremiumStatus, isUserPremiumRevokeLocked } = await import('./userDirectory');
    if (await isUserPremiumRevokeLocked(publicId)) {
      throw new HttpError(403, 'Premium access was revoked for this account', 'PREMIUM_REVOKED');
    }
    const until = await getUserPremiumStatus(publicId);
    if (isPremiumUntilActiveLocal(until)) {
      return { premiumUntilMs: until };
    }
    const ps = await resolvePaidStatusForOrder(orderId);
    if (!isPaymentCompletedStatus(ps)) {
      throw new HttpError(409, 'Payment already used for premium', 'ORDER_ALREADY_ACTIVATED');
    }
    const out = await writePremiumForOrder(orderId, { publicId, planId, phone });
    return { premiumUntilMs: out.premiumUntilMs };
  }

  if (!tracked?.public_id || !tracked.plan_id) {
    await upsertPendingIntent({
      orderId,
      publicId,
      planId,
      buyerPhone: phone,
      provider: PAYMENT_PROVIDERS.SONICPESA,
    });
    tracked = await getIntent(orderId);
  }

  const ps = await resolvePaidStatusForOrder(orderId);

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

export function providerHealthSnapshot(): {
  paymentProvider: PaymentProviderId;
  configured: boolean;
  sonicConfigured: boolean;
} {
  const sonicConfigured = isSonicPesaConfigured();
  return {
    paymentProvider: PAYMENT_PROVIDERS.SONICPESA,
    configured: sonicConfigured,
    sonicConfigured,
  };
}
