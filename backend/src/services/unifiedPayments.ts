import {
  fetchSonicOrderStatus,
  isSonicPaymentCompleted,
  isSonicRawPaymentCompleted,
  mapSonicInitiateUserError,
  tryCreateSonicOrder,
} from './sonicPesa';
import {
  fetchAuraxOrderStatus,
  isAuraxConfigured,
  isAuraxPaymentCompleted,
  tryCreateAuraxOrder,
} from './auraxPay';
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
import { normalizePhoneToLocal0, detectTzMobileNetwork, isSupportedSonicPushWallet } from '../lib/tzPhone';
import {
  isMobileMoneyStkSendFailure,
  isPaymentRateLimitError,
} from '../lib/paymentProviderErrors';

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
  const nest =
    p.data && typeof p.data === 'object' && !Array.isArray(p.data)
      ? (p.data as Record<string, unknown>)
      : Array.isArray(p.data) && p.data.length > 0 && typeof p.data[0] === 'object'
        ? (p.data[0] as Record<string, unknown>)
        : {};
  const nestMeta =
    nest.metadata && typeof nest.metadata === 'object' && !Array.isArray(nest.metadata)
      ? (nest.metadata as Record<string, unknown>)
      : {};
  const publicId = String(
    meta.external_id ??
      meta.public_id ??
      meta.publicId ??
      nestMeta.external_id ??
      nestMeta.public_id ??
      nest.external_id ??
      nest.public_id ??
      p.public_id ??
      p.publicId ??
      p.external_id ??
      '',
  ).trim();
  const planId = String(
    meta.plan_id ??
      meta.planId ??
      nestMeta.plan_id ??
      nestMeta.planId ??
      nest.plan_id ??
      nest.planId ??
      p.plan_id ??
      p.planId ??
      '',
  ).trim();
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
  if (!isSupportedSonicPushWallet(localPhone)) {
    logger.warn(
      { phone: localPhone, network: detectTzMobileNetwork(localPhone) },
      'payment_start_unsupported_prefix',
    );
  }
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
    publicId: input.publicId,
    planId: input.planId,
  });
  if (!sonic.ok || !sonic.orderId) {
    const rawMsg = sonic.message || '';
    const rawCode = sonic.errorCode ?? '';
    // Prod: Sonic delivers Tigo fine but Vodacom/M-Pesa STK often fails — fall back to Aurax (EaMax).
    const canAuraxFallback =
      isAuraxConfigured() &&
      !isPaymentRateLimitError(rawMsg, rawCode) &&
      (isMobileMoneyStkSendFailure(rawMsg, rawCode) ||
        detectTzMobileNetwork(localPhone) === 'vodacom' ||
        detectTzMobileNetwork(localPhone) === 'mo_mobile');

    if (canAuraxFallback) {
      const clientOrderId = `ax_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
      logger.warn(
        { phone: localPhone, network: detectTzMobileNetwork(localPhone), rawMsg, rawCode },
        'payment_sonic_stk_failed_trying_aurax',
      );
      const aurax = await tryCreateAuraxOrder({
        localPhone,
        amountTzs,
        buyerName,
        buyerEmail,
        publicId: input.publicId,
        planId: input.planId,
        clientOrderId,
      });
      if (aurax.ok && aurax.orderId) {
        await upsertPendingIntent({
          orderId: aurax.orderId,
          publicId: input.publicId,
          planId: input.planId,
          amountTzs,
          buyerPhone: localPhone,
          provider: PAYMENT_PROVIDERS.AURAX,
          providerPayload: { ...aurax.raw, fallbackFrom: 'sonicpesa', clientOrderId },
        });
        return {
          orderId: aurax.orderId,
          message: aurax.message,
          provider: PAYMENT_PROVIDERS.AURAX,
          status: 'pending',
        };
      }
      logger.warn(
        { phone: localPhone, auraxMsg: aurax.errorMessage ?? aurax.message },
        'payment_aurax_fallback_failed',
      );
    }

    const userMsg =
      (sonic.errorMessage && sonic.errorMessage.trim()) ||
      mapSonicInitiateUserError(localPhone, sonic.message, sonic.errorCode ?? '');
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

  // create_order_simple can block ~60s; user may already have paid. Activate if Sonic already shows paid.
  try {
    await ensurePremiumActivatedForPaidOrder(
      sonic.orderId,
      { publicId: input.publicId, planId: input.planId, phone: localPhone },
      { trustPaid: false },
    );
  } catch (e) {
    logger.warn(
      { orderId: sonic.orderId, err: e instanceof Error ? e.message : String(e) },
      'payment_start_early_activate_failed',
    );
  }

  return {
    orderId: sonic.orderId,
    message: sonic.message,
    provider: PAYMENT_PROVIDERS.SONICPESA,
    status: 'pending',
  };
}

async function resolvePaidStatusForOrder(orderId: string): Promise<string> {
  const intent = await getIntent(orderId);
  const provider = String(intent?.payment_provider ?? '').toLowerCase();
  if (provider === PAYMENT_PROVIDERS.AURAX && isAuraxConfigured()) {
    const { paymentStatus } = await fetchAuraxOrderStatus(orderId);
    if (isAuraxPaymentCompleted(paymentStatus)) return paymentStatus || 'COMPLETED';
    return paymentStatus;
  }
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

  const { getUserPremiumStatus } = await import('./userDirectory.js');
  const existing = await getUserPremiumStatus(trimmed);
  if (isPremiumUntilActiveLocal(existing)) return existing;

  const pool = getPool();
  if (!pool) return null;
  await ensurePaymentIntentsTable();

  // Catch paid orders that never granted premium (missed webhook / status lag / stuck stamp).
  const res = await pool.query<{ order_id: string; status: string; provider_status: string | null }>(
    `SELECT order_id, status, provider_status
     FROM payment_intents
     WHERE public_id = $1
       AND updated_at > now() - interval '90 days'
       AND status NOT IN ('FAILED', 'CANCELLED', 'EXPIRED', 'REJECTED', 'ERROR')
     ORDER BY updated_at DESC
     LIMIT 25`,
    [trimmed],
  );

  for (const row of res.rows) {
    const localPaid =
      isPaymentCompletedStatus(row.status) || isPaymentCompletedStatus(row.provider_status ?? '');
    let paid = localPaid;
    if (!paid) {
      const ps = await resolvePaidStatusForOrder(row.order_id);
      paid = isPaymentCompletedStatus(ps);
    }
    if (!paid) continue;

    // Verified paid order must unlock (trustPaid also clears/bypass revoke for never-granted repairs).
    const act = await ensurePremiumActivatedForPaidOrder(
      row.order_id,
      { publicId: trimmed },
      { trustPaid: true },
    );
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

/**
 * Handle intents already stamped activated_at_ms.
 * - Active premium → success
 * - Note has sonicpesa:orderId and premium expired → one-shot window, do not re-grant
 * - Stamp without grant marker (delete/race stuck) → repair when paid/trustPaid
 * - Admin revoke + grant marker → honor revoke unless trustPaid repair of never-granted
 */
async function resolveActivatedIntentPremium(
  orderId: string,
  identity: { publicId: string; planId: string; phone: string },
  opts?: { trustPaid?: boolean },
): Promise<{ activated: boolean; premiumUntilMs?: number }> {
  const { getUserPremiumRecord } = await import('./userDirectory.js');
  const rec = await getUserPremiumRecord(identity.publicId);
  if (isPremiumUntilActiveLocal(rec.premiumUntilMs)) {
    return { activated: true, premiumUntilMs: rec.premiumUntilMs };
  }

  const note = rec.note ?? '';
  const grantedThisOrder = note.includes(`sonicpesa:${orderId}`);
  if (grantedThisOrder) {
    // Subscription window already consumed for this order (expired or revoked after grant).
    return { activated: false };
  }

  // activated_at_ms set but premium never written for this order (legacy delete stamp / failed write).
  if (!opts?.trustPaid) {
    return { activated: false };
  }

  logger.warn({ orderId, publicId: identity.publicId }, 'payment_repair_activated_without_premium');
  const out = await writePremiumForOrder(orderId, identity);
  return { activated: true, premiumUntilMs: out.premiumUntilMs };
}

export async function activatePremiumIfCompletedOrder(
  orderId: string,
  overrides?: ActivateOverrides,
  opts?: { trustPaid?: boolean },
): Promise<{ activated: boolean; premiumUntilMs?: number }> {
  const intent = await getIntent(orderId);
  const identity = resolveOrderIdentity(orderId, intent, overrides);
  if (!identity.publicId || !identity.planId) {
    logger.warn({ orderId }, 'payment_activate_missing_metadata');
    return { activated: false };
  }
  if (intent?.activated_at_ms != null) {
    return resolveActivatedIntentPremium(orderId, identity, opts);
  }

  // Webhook already said paid — do not wait on Sonic order_status lag (main miss cause).
  if (!opts?.trustPaid) {
    const ps = await resolvePaidStatusForOrder(orderId);
    if (!isPaymentCompletedStatus(ps)) {
      return { activated: false };
    }
    await updateIntentStatus({ orderId, providerStatus: ps || 'COMPLETED' });
  } else {
    await updateIntentStatus({ orderId, providerStatus: 'COMPLETED' });
  }

  const out = await writePremiumForOrder(orderId, identity);
  return { activated: true, premiumUntilMs: out.premiumUntilMs };
}

export async function ensurePremiumActivatedForPaidOrder(
  orderId: string,
  overrides?: ActivateOverrides,
  opts?: { trustPaid?: boolean },
): Promise<{ activated: boolean; premiumUntilMs?: number }> {
  const trimmed = orderId.trim();
  if (!trimmed) return { activated: false };

  let intent = await getIntent(trimmed);
  // Fill missing identity from overrides so webhook/poll can activate after late intent create.
  if (
    overrides &&
    (!intent?.public_id || !intent?.plan_id) &&
    (overrides.publicId || overrides.planId)
  ) {
    await upsertPendingIntent({
      orderId: trimmed,
      publicId: overrides.publicId ?? intent?.public_id ?? undefined,
      planId: overrides.planId ?? intent?.plan_id ?? undefined,
      buyerPhone: overrides.phone ?? intent?.buyer_phone ?? undefined,
      provider: PAYMENT_PROVIDERS.SONICPESA,
    });
    intent = await getIntent(trimmed);
  }

  const identity = resolveOrderIdentity(trimmed, intent, overrides);
  if (!identity.publicId || !identity.planId) {
    logger.warn({ orderId: trimmed }, 'payment_force_activate_missing_metadata');
    return { activated: false };
  }

  const { isUserPremiumRevokeLocked } = await import('./userDirectory.js');
  // Admin revoke lock blocks casual paths — verified paid (trustPaid) still unlocks.
  if (!opts?.trustPaid && (await isUserPremiumRevokeLocked(identity.publicId))) {
    return { activated: false };
  }

  if (intent?.activated_at_ms != null) {
    return resolveActivatedIntentPremium(trimmed, identity, opts);
  }

  const act = await activatePremiumIfCompletedOrder(trimmed, overrides, opts);
  if (act.activated && isPremiumUntilActiveLocal(act.premiumUntilMs)) return act;

  return { activated: false };
}

/**
 * Background safety net: activate recent paid intents that never wrote premium_until_ms
 * (missed webhook, Sonic status lag after paid, client left before poll finished).
 */
export async function reconcileUnactivatedPaidIntents(limit = 40): Promise<number> {
  const pool = getPool();
  if (!pool) return 0;
  await ensurePaymentIntentsTable();

  const res = await pool.query<{
    order_id: string;
    public_id: string | null;
    plan_id: string | null;
    status: string;
    provider_status: string | null;
    activated_at_ms: string | null;
  }>(
    `SELECT order_id, public_id, plan_id, status, provider_status, activated_at_ms
     FROM payment_intents
     WHERE public_id IS NOT NULL AND public_id <> ''
       AND plan_id IS NOT NULL AND plan_id <> ''
       AND updated_at > now() - interval '14 days'
       AND status NOT IN ('FAILED', 'CANCELLED', 'EXPIRED', 'REJECTED', 'ERROR')
     ORDER BY updated_at DESC
     LIMIT $1`,
    [Math.max(1, Math.min(100, limit))],
  );

  let activated = 0;
  for (const row of res.rows) {
    try {
      const alreadyCompletedLocal =
        isPaymentCompletedStatus(row.status) || isPaymentCompletedStatus(row.provider_status ?? '');
      const ps = alreadyCompletedLocal ? 'COMPLETED' : await resolvePaidStatusForOrder(row.order_id);
      if (!isPaymentCompletedStatus(ps)) continue;

      const act = await ensurePremiumActivatedForPaidOrder(
        row.order_id,
        { publicId: row.public_id ?? undefined, planId: row.plan_id ?? undefined },
        { trustPaid: true },
      );
      if (act.activated) {
        activated += 1;
        logger.info(
          { orderId: row.order_id, publicId: row.public_id, premiumUntilMs: act.premiumUntilMs },
          'payment_reconcile_sweep_activated',
        );
      }
    } catch (e) {
      logger.warn(
        { orderId: row.order_id, err: e instanceof Error ? e.message : String(e) },
        'payment_reconcile_sweep_failed',
      );
    }
  }
  return activated;
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
  if (
    local?.activated_at_ms != null ||
    isPaymentCompletedStatus(local?.status ?? '') ||
    isPaymentCompletedStatus(local?.provider_status ?? '')
  ) {
    // Local ledger says paid (or stamped) — activate / repair immediately; never leave paid stuck.
    const act = await ensurePremiumActivatedForPaidOrder(
      trimmed,
      {
        publicId: local?.public_id ?? undefined,
        planId: local?.plan_id ?? undefined,
      },
      { trustPaid: true },
    );
    if (act.activated && isPremiumUntilActiveLocal(act.premiumUntilMs)) {
      return {
        status: 'COMPLETED',
        resultcode: '000',
        raw: { data: [{ payment_status: 'COMPLETED', order_id: trimmed }] },
        activated: true,
        premiumUntilMs: act.premiumUntilMs,
        ...intentMeta,
      };
    }
    // Still paid at ledger — surface COMPLETED so the client keeps confirming.
    return {
      status: 'COMPLETED',
      resultcode: '000',
      raw: { data: [{ payment_status: 'COMPLETED', order_id: trimmed }] },
      activated: false,
      ...intentMeta,
    };
  }

  const provider = String(local?.payment_provider ?? '').toLowerCase();
  if (provider === PAYMENT_PROVIDERS.AURAX && isAuraxConfigured()) {
    const { ok, paymentStatus, raw } = await fetchAuraxOrderStatus(trimmed);
    if (paymentStatus) {
      await updateIntentStatus({
        orderId: trimmed,
        providerStatus: paymentStatus,
        providerPayload: raw,
      });
    }
    if (isAuraxPaymentCompleted(paymentStatus)) {
      const intentAfter = (await getIntent(trimmed)) ?? local;
      const act = await ensurePremiumActivatedForPaidOrder(trimmed, intentOverrides(intentAfter), {
        trustPaid: true,
      });
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
    return { status: paymentStatus || (ok ? 'PENDING' : 'PENDING'), raw, ...intentMeta };
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
    const act = await ensurePremiumActivatedForPaidOrder(trimmed, intentOverrides(intentAfter), {
      trustPaid: true,
    });
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
  const localPaid =
    isPaymentCompletedStatus(tracked?.status ?? '') ||
    isPaymentCompletedStatus(tracked?.provider_status ?? '');

  if (ps) {
    await updateIntentStatus({ orderId, providerStatus: ps });
  }

  if (!isPaymentCompletedStatus(ps) && !localPaid) {
    const code = isPaymentTerminalFailure(ps) ? 409 : 402;
    throw new HttpError(code, 'Payment not completed', 'NOT_COMPLETED');
  }

  const act = await ensurePremiumActivatedForPaidOrder(
    orderId,
    { publicId, planId, phone },
    { trustPaid: true },
  );
  if (act.activated && isPremiumUntilActiveLocal(act.premiumUntilMs)) {
    return { premiumUntilMs: act.premiumUntilMs! };
  }

  const { getUserPremiumStatus, isUserPremiumRevokeLocked } = await import('./userDirectory.js');
  if (await isUserPremiumRevokeLocked(publicId)) {
    throw new HttpError(403, 'Premium access was revoked for this account', 'PREMIUM_REVOKED');
  }
  const until = await getUserPremiumStatus(publicId);
  if (isPremiumUntilActiveLocal(until)) {
    return { premiumUntilMs: until };
  }
  throw new HttpError(500, 'Payment completed but premium could not be activated', 'ACTIVATE_FAILED');
}

export function providerHealthSnapshot(): {
  paymentProvider: PaymentProviderId;
  configured: boolean;
  sonicConfigured: boolean;
  auraxConfigured: boolean;
} {
  const sonicConfigured = isSonicPesaConfigured();
  const auraxConfigured = isAuraxConfigured();
  return {
    paymentProvider: PAYMENT_PROVIDERS.SONICPESA,
    configured: sonicConfigured,
    sonicConfigured,
    auraxConfigured,
  };
}
