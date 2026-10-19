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
  markIntentPremiumGranted,
  upsertPendingIntent,
  updateIntentStatus,
} from './paymentIntents';
import { getPool } from '../db/pool';
import { activatePremiumForUser } from './premiumActivation';
import { HttpError } from '../middleware/errorHandler';
import {
  clearPaymentStartCooldown,
  getPaymentStartCooldownEntry,
  getRecentPaymentStartEntry,
  isPaymentStartPendingRetryWindow,
  markPaymentStartSent,
  paymentStartCooldownMessage,
} from './paymentStartCooldown';
import {
  isMobileMoneyStkSendFailure,
  isPaymentApiThrottleError,
  isPaymentRateLimitError,
} from '../lib/paymentProviderErrors';
import {
  detectTzMobileNetwork,
  isAirtelLocalPhone,
  isHalotelLocalPhone,
  isSupportedSonicPushWallet,
  isTigoYasLocalPhone,
  normalizePhoneToLocal0,
  walletLabelForLocalPhone,
} from '../lib/tzPhone';

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

/** Clear post-STK cooldown when the linked order is dead — lets failed-first numbers retry. */
async function refreshPaymentStartCooldownForPhone(localPhone: string): Promise<void> {
  const entry = getRecentPaymentStartEntry(localPhone) ?? getPaymentStartCooldownEntry(localPhone);
  if (!entry) return;

  if (Date.now() - entry.at > 15 * 60 * 1000) {
    clearPaymentStartCooldown(localPhone);
    logger.info({ phone: localPhone, orderId: entry.orderId }, 'payment_cooldown_cleared_stale');
    return;
  }

  if (!entry.orderId) {
    // Legacy entry without order id — expire with the normal window only.
    return;
  }

  try {
    const intent = await getIntent(entry.orderId);
    const provider = String(intent?.payment_provider ?? entry.provider ?? '').toLowerCase();
    let ok = false;
    let paymentStatus = '';
    if (provider === PAYMENT_PROVIDERS.AURAX && isAuraxConfigured()) {
      const aurax = await fetchAuraxOrderStatus(entry.orderId);
      ok = aurax.ok;
      paymentStatus = aurax.paymentStatus;
    } else {
      const sonic = await fetchSonicOrderStatus(entry.orderId);
      ok = sonic.ok;
      paymentStatus = sonic.paymentStatus;
    }
    const ps = String(paymentStatus ?? '').trim().toUpperCase();
    if (!ok && !ps) {
      clearPaymentStartCooldown(localPhone);
      logger.info({ phone: localPhone, orderId: entry.orderId }, 'payment_cooldown_cleared_missing_order');
      return;
    }
    if (isPaymentTerminalFailure(ps) || isPaymentCompletedStatus(ps)) {
      clearPaymentStartCooldown(localPhone);
      logger.info(
        { phone: localPhone, orderId: entry.orderId, paymentStatus: ps },
        'payment_cooldown_cleared_terminal_order',
      );
      return;
    }
    // Still PENDING after ~45s — likely silent STK miss; free the user to retry.
    if (isPaymentStartPendingRetryWindow(localPhone)) {
      clearPaymentStartCooldown(localPhone);
      logger.info(
        { phone: localPhone, orderId: entry.orderId, paymentStatus: ps || 'PENDING' },
        'payment_cooldown_cleared_pending_retry',
      );
    }
  } catch (e) {
    logger.warn(
      { phone: localPhone, orderId: entry.orderId, err: e instanceof Error ? e.message : String(e) },
      'payment_cooldown_refresh_skipped',
    );
  }
}

function canUseAuraxStkFallback(localPhone: string): boolean {
  return isSupportedSonicPushWallet(localPhone);
}

/**
 * Halopesa + Mixx/Yas + Airtel often never receive Sonic Push USSD.
 * When Aurax is configured, route them there first so the PIN prompt reaches the phone.
 */
function shouldPreferAuraxForPhone(localPhone: string): boolean {
  return (
    isAuraxConfigured() &&
    (isHalotelLocalPhone(localPhone) ||
      isTigoYasLocalPhone(localPhone) ||
      isAirtelLocalPhone(localPhone))
  );
}

/**
 * If the last "successful" Aurax order is still pending (no PIN on phone),
 * skip Aurax prefer and try Sonic so the user is not stuck in a silent loop.
 */
function shouldSkipAuraxPreferAfterSilentMiss(localPhone: string): boolean {
  const recent = getRecentPaymentStartEntry(localPhone);
  if (!recent?.orderId) return false;
  if (String(recent.provider ?? '').toLowerCase() !== PAYMENT_PROVIDERS.AURAX) return false;
  return isPaymentStartPendingRetryWindow(localPhone);
}

/** Fall back to Aurax when Sonic is busy/throttled, times out, or STK never left the gateway. */
function shouldFallbackSonicToAurax(args: {
  localPhone: string;
  rawMsg: string;
  rawCode: string;
  errorCode?: string;
}): boolean {
  if (!isAuraxConfigured() || !canUseAuraxStkFallback(args.localPhone)) return false;
  // Per-number Sonic quota — do not open a second gateway charge attempt.
  if (
    args.errorCode === 'PAYMENT_RATE_LIMIT' ||
    isPaymentRateLimitError(args.rawMsg, args.rawCode)
  ) {
    return false;
  }
  return (
    args.errorCode === 'PAYMENT_BUSY' ||
    args.errorCode === 'GATEWAY_TIMEOUT' ||
    args.errorCode === 'GATEWAY_ERROR' ||
    isPaymentApiThrottleError(args.rawMsg, args.rawCode) ||
    isMobileMoneyStkSendFailure(args.rawMsg, args.rawCode) ||
    /huduma ina shughuli|too many attempts|too many requests|rate limited/i.test(args.rawMsg) ||
    /gateway timeout|timed out|abort|fetch failed|network|econnreset/i.test(args.rawMsg) ||
    /hayajatumika|could not send|push failed|upstream|9012|9009|999/i.test(
      `${args.rawMsg} ${args.rawCode}`,
    )
  );
}

async function startAuraxPaymentIntent(args: {
  localPhone: string;
  amountTzs: number;
  buyerName: string;
  buyerEmail: string;
  publicId: string;
  planId: string;
  fallbackFrom?: string;
}): Promise<{
  orderId: string;
  message: string;
  provider: PaymentProviderId;
  status: string;
} | null> {
  if (!isAuraxConfigured()) return null;
  try {
    const clientOrderId = `ax_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
    const aurax = await tryCreateAuraxOrder({
      localPhone: args.localPhone,
      amountTzs: args.amountTzs,
      buyerName: args.buyerName,
      buyerEmail: args.buyerEmail,
      publicId: args.publicId,
      planId: args.planId,
      clientOrderId,
    });
    if (!aurax.ok || !aurax.orderId) {
      logger.warn(
        {
          phone: args.localPhone,
          network: detectTzMobileNetwork(args.localPhone),
          auraxMsg: aurax.errorMessage ?? aurax.message,
        },
        'payment_aurax_create_failed',
      );
      return null;
    }
    await upsertPendingIntent({
      orderId: aurax.orderId,
      publicId: args.publicId,
      planId: args.planId,
      amountTzs: args.amountTzs,
      buyerPhone: args.localPhone,
      provider: PAYMENT_PROVIDERS.AURAX,
      providerPayload: {
        ...aurax.raw,
        ...(args.fallbackFrom ? { fallbackFrom: args.fallbackFrom } : { preferredRoute: 'aurax' }),
        clientOrderId,
      },
    });
    markPaymentStartSent(args.localPhone, aurax.orderId, PAYMENT_PROVIDERS.AURAX);
    return {
      orderId: aurax.orderId,
      message: aurax.message,
      provider: PAYMENT_PROVIDERS.AURAX,
      status: 'pending',
    };
  } catch (e) {
    logger.warn(
      {
        phone: args.localPhone,
        network: detectTzMobileNetwork(args.localPhone),
        err: e instanceof Error ? e.message : String(e),
      },
      'payment_aurax_create_threw',
    );
    return null;
  }
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
    const wallet = walletLabelForLocalPhone(localPhone);
    throw new HttpError(
      400,
      `Nambari hii (${wallet}) haipokei Push USSD. Tumia M-Pesa (074–079), Tigo/Yas (065/067/070/071/077), Airtel (066/068/069/078) au Halopesa (061–063).`,
      'UNSUPPORTED_WALLET',
    );
  }
  const amountTzs = Math.trunc(input.amountTzs);
  if (amountTzs < 1) {
    throw new HttpError(400, 'Amount must be at least 1 TZS', 'BAD_AMOUNT');
  }

  // Keep payments on the existing subscribed User id when phone matches.
  const { findCanonicalUserByPhone, isPremiumUntilActive, registerPublicUser } = await import(
    './userDirectory.js'
  );
  let publicId = String(input.publicId ?? '').trim();
  const canonical = await findCanonicalUserByPhone(localPhone);
  if (canonical && isPremiumUntilActive(canonical.premiumUntilMs) && canonical.id) {
    if (canonical.id !== publicId) {
      logger.info(
        { from: publicId, to: canonical.id, phone: localPhone },
        'payment_start_recovered_active_user_id',
      );
    }
    publicId = canonical.id;
  }
  await registerPublicUser({
    publicId,
    profileUsername: publicId,
    phone: localPhone,
  });
  input = { ...input, publicId };

  await getSelectedPaymentProvider();

  if (!isProviderConfigured() && !isAuraxConfigured()) {
    throw new HttpError(
      503,
      'SonicPesa haijasanidi kwenye seva. Wasiliana na admin.',
      'SONIC_NOT_CONFIGURED',
    );
  }

  const buyerName = (input.buyerName ?? publicId).trim() || 'Mteja';
  const buyerEmail = (input.buyerEmail ?? `${publicId}@supasoka.app`).trim();

  await refreshPaymentStartCooldownForPhone(localPhone);
  const cooldownMsg = paymentStartCooldownMessage(localPhone);
  if (cooldownMsg) {
    throw new HttpError(429, cooldownMsg, 'PAYMENT_COOLDOWN');
  }

  let auraxAlreadyTried = false;

  // Halopesa / Tigo-Yas / Airtel → Aurax first so Push USSD reaches the handset.
  // Skip prefer if a recent Aurax order looks like a silent STK miss — try Sonic instead.
  const skipAuraxPrefer = shouldSkipAuraxPreferAfterSilentMiss(localPhone);
  if (shouldPreferAuraxForPhone(localPhone) && !skipAuraxPrefer) {
    logger.info(
      {
        phone: localPhone,
        network: detectTzMobileNetwork(localPhone),
        wallet: walletLabelForLocalPhone(localPhone),
      },
      'payment_prefer_aurax_for_wallet',
    );
    const auraxFirst = await startAuraxPaymentIntent({
      localPhone,
      amountTzs,
      buyerName,
      buyerEmail,
      publicId,
      planId: input.planId,
    });
    auraxAlreadyTried = true;
    if (auraxFirst) return auraxFirst;
    logger.warn(
      { phone: localPhone, network: detectTzMobileNetwork(localPhone) },
      'payment_aurax_preferred_failed_trying_sonic',
    );
  } else if (skipAuraxPrefer) {
    logger.info(
      {
        phone: localPhone,
        network: detectTzMobileNetwork(localPhone),
        recent: getRecentPaymentStartEntry(localPhone),
      },
      'payment_skip_aurax_prefer_silent_miss_trying_sonic',
    );
  }

  if (!isProviderConfigured()) {
    // Aurax preferred path failed and Sonic is not configured.
    throw new HttpError(
      503,
      'Hatukuweza kutuma ombi la malipo. Wasiliana na admin.',
      'PAYMENT_NOT_CONFIGURED',
    );
  }

  const sonic = await tryCreateSonicOrder({
    buyerEmail,
    buyerName,
    localPhone,
    amountTzs,
    publicId,
    planId: input.planId,
  });
  if (!sonic.ok || !sonic.orderId) {
    const rawMsg = sonic.message || sonic.errorMessage || '';
    const rawCode = sonic.errorCode ?? '';
    const canFallback =
      !auraxAlreadyTried &&
      shouldFallbackSonicToAurax({
        localPhone,
        rawMsg,
        rawCode,
        errorCode: sonic.errorCode,
      });
    if (canFallback) {
      logger.warn(
        {
          phone: localPhone,
          network: detectTzMobileNetwork(localPhone),
          wallet: walletLabelForLocalPhone(localPhone),
          rawMsg,
          rawCode,
          errorCode: sonic.errorCode,
          stkFailure: isMobileMoneyStkSendFailure(rawMsg, rawCode),
          busy:
            sonic.errorCode === 'PAYMENT_BUSY' ||
            sonic.errorCode === 'GATEWAY_TIMEOUT' ||
            isPaymentApiThrottleError(rawMsg, rawCode),
        },
        'payment_sonic_failed_trying_aurax',
      );
      const aurax = await startAuraxPaymentIntent({
        localPhone,
        amountTzs,
        buyerName,
        buyerEmail,
        publicId,
        planId: input.planId,
        fallbackFrom: 'sonicpesa',
      });
      if (aurax) return aurax;
    }

    const userMsg =
      (sonic.errorMessage && sonic.errorMessage.trim()) ||
      mapSonicInitiateUserError(localPhone, sonic.message, sonic.errorCode ?? '');
    const rateLimited =
      sonic.errorCode === 'PAYMENT_RATE_LIMIT' ||
      userMsg.includes('majaribio mengi') ||
      userMsg.includes('umefanya majaribio') ||
      userMsg.includes('umejaribu mara nyingi');
    const busy =
      sonic.errorCode === 'PAYMENT_BUSY' ||
      sonic.errorCode === 'GATEWAY_TIMEOUT' ||
      userMsg.includes('huduma ina shughuli');
    throw new HttpError(
      rateLimited || busy ? 429 : 400,
      userMsg,
      rateLimited ? 'PAYMENT_RATE_LIMIT' : busy ? 'PAYMENT_BUSY' : 'SONIC_CREATE_FAILED',
    );
  }

  await upsertPendingIntent({
    orderId: sonic.orderId,
    publicId,
    planId: input.planId,
    amountTzs,
    buyerPhone: localPhone,
    provider: PAYMENT_PROVIDERS.SONICPESA,
    providerPayload: sonic.raw,
  });

  // User may already have paid while create_order was in flight. Activate if Sonic already shows paid.
  try {
    await ensurePremiumActivatedForPaidOrder(
      sonic.orderId,
      { publicId, planId: input.planId, phone: localPhone },
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

  // Only never-granted paid orders — already-granted must not re-extend after expiry.
  const res = await pool.query<{ order_id: string; status: string; provider_status: string | null }>(
    `SELECT order_id, status, provider_status
     FROM payment_intents
     WHERE public_id = $1
       AND premium_granted_until_ms IS NULL
       AND updated_at > now() - interval '14 days'
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
  const intent = await getIntent(orderId);
  const provider = String(intent?.payment_provider ?? '').toLowerCase();
  const notePrefix = provider === PAYMENT_PROVIDERS.AURAX ? 'aurax' : 'sonicpesa';
  const activated = await activatePremiumForUser({
    publicId: identity.publicId,
    planId: identity.planId,
    phone: identity.phone,
    note: `${notePrefix}:${orderId}`,
  });
  await markIntentActivated(orderId);
  await markIntentPremiumGranted(orderId, activated.premiumUntilMs);
  logger.info(
    { orderId, publicId: identity.publicId, planId: identity.planId, premiumUntilMs: activated.premiumUntilMs },
    'payment_activated_premium',
  );
  return { premiumUntilMs: activated.premiumUntilMs };
}

/** Fresh activation race: stamp set but premium write failed — only repair within this window. */
const PREMIUM_GRANT_REPAIR_MS = 15 * 60 * 1000;

/**
 * Handle intents already stamped activated_at_ms.
 * One-shot: once premium_granted_until_ms is set (or legacy grant marker / old stamp),
 * never write a new premium window for this order after natural expiry.
 */
async function resolveActivatedIntentPremium(
  orderId: string,
  identity: { publicId: string; planId: string; phone: string },
  opts?: { trustPaid?: boolean },
): Promise<{ activated: boolean; premiumUntilMs?: number }> {
  const intent = await getIntent(orderId);
  const { getUserPremiumRecord } = await import('./userDirectory.js');
  const rec = await getUserPremiumRecord(identity.publicId);

  const grantedUntilRaw = intent?.premium_granted_until_ms;
  const alreadyGranted =
    grantedUntilRaw != null &&
    String(grantedUntilRaw).trim() !== '' &&
    Number.isFinite(Number(grantedUntilRaw));

  if (alreadyGranted) {
    if (isPremiumUntilActiveLocal(rec.premiumUntilMs)) {
      return { activated: true, premiumUntilMs: rec.premiumUntilMs };
    }
    // Window for this payment already consumed — do not re-grant after expiry.
    return { activated: false };
  }

  if (isPremiumUntilActiveLocal(rec.premiumUntilMs)) {
    // User is active; backfill one-shot marker without extending.
    await markIntentPremiumGranted(orderId, rec.premiumUntilMs);
    return { activated: true, premiumUntilMs: rec.premiumUntilMs };
  }

  const note = rec.note ?? '';
  const grantedThisOrder =
    note.includes(`sonicpesa:${orderId}`) || note.includes(`aurax:${orderId}`);
  if (grantedThisOrder) {
    const stamp = Number(rec.premiumUntilMs) || Number(intent?.activated_at_ms) || Date.now();
    await markIntentPremiumGranted(orderId, stamp);
    return { activated: false };
  }

  const activatedAt = Number(intent?.activated_at_ms ?? 0);
  const freshStamp =
    Number.isFinite(activatedAt) &&
    activatedAt > 0 &&
    Date.now() - activatedAt < PREMIUM_GRANT_REPAIR_MS;

  // Legacy activated stamp without grant column: treat as already consumed unless very fresh.
  if (!freshStamp || !opts?.trustPaid) {
    if (Number.isFinite(activatedAt) && activatedAt > 0) {
      await markIntentPremiumGranted(orderId, activatedAt);
    }
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
  // Admin revoke blocks re-unlock from old orders. A brand-new unpaid grant for this
  // order still proceeds — activatePremiumForUser clears the revoke marker.
  if (await isUserPremiumRevokeLocked(identity.publicId)) {
    const alreadyConsumed =
      intent?.premium_granted_until_ms != null || intent?.activated_at_ms != null;
    if (alreadyConsumed) {
      return { activated: false };
    }
  }

  if (intent?.premium_granted_until_ms != null) {
    const { getUserPremiumRecord } = await import('./userDirectory.js');
    const rec = await getUserPremiumRecord(identity.publicId);
    if (isPremiumUntilActiveLocal(rec.premiumUntilMs)) {
      return { activated: true, premiumUntilMs: rec.premiumUntilMs };
    }
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
       AND premium_granted_until_ms IS NULL
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
  const { orderId } = args;
  let planId = String(args.planId ?? '').trim();
  let publicId = String(args.publicId ?? '').trim();
  if (!orderId || !publicId || !planId) {
    throw new HttpError(400, 'Missing orderId/publicId/planId', 'MISSING_FIELDS');
  }

  let tracked = await getIntent(orderId);
  const phoneNorm = normalizePhoneToLocal0(args.phone || tracked?.buyer_phone || '');
  const phone = phoneNorm.local ?? String(args.phone ?? tracked?.buyer_phone ?? '').trim();

  // Prefer the paid order's original public id (and any still-active phone match)
  // so an app update that minted a new local User-xxxxx cannot block unlock.
  if (tracked?.public_id && tracked.public_id !== publicId) {
    const intentPhone = normalizePhoneToLocal0(tracked.buyer_phone || phone);
    const samePhone =
      !!phone &&
      !!intentPhone.local &&
      intentPhone.local === (phoneNorm.local || phone);
    if (samePhone || !phone) {
      logger.info(
        { orderId, from: publicId, to: tracked.public_id },
        'payment_confirm_adopting_intent_public_id',
      );
      publicId = tracked.public_id;
    } else {
      const { findCanonicalUserByPhone, isPremiumUntilActive } = await import('./userDirectory.js');
      const canonical = phone ? await findCanonicalUserByPhone(phone) : null;
      if (canonical && isPremiumUntilActive(canonical.premiumUntilMs)) {
        publicId = canonical.id;
      } else if (tracked.public_id) {
        publicId = tracked.public_id;
      } else {
        throw new HttpError(409, 'Order belongs to another user', 'PUBLIC_ID_MISMATCH');
      }
    }
  }
  if (tracked?.plan_id && tracked.plan_id !== planId) {
    logger.info(
      { orderId, clientPlanId: planId, trackedPlanId: tracked.plan_id },
      'payment_confirm_adopting_tracked_plan_id',
    );
    planId = tracked.plan_id;
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
