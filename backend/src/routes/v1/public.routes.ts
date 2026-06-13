import { Router } from 'express';
import { fetchPublicConfig, fetchPublicConfigMeta } from '../../services/publicConfig';
import {
  buildAppUpdatePayload,
  fetchAppUpdateSettings,
  readClientAppIdentity,
  redactPlaybackSecretsFromConfig,
  stripCatalogForForcedUpdate,
} from '../../services/appUpdatePolicy';
import { assertSupportedAppClient, resolvePlaybackForChannel } from '../../services/playbackAccess';
import { registerPublicUser, getUserPremiumRecord } from '../../services/userDirectory';
import { logger } from '../../lib/logger';
import {
  getIntent,
  upsertPendingIntent,
  updateIntentStatus,
} from '../../services/paymentIntents';
import { getSelectedPaymentProvider } from '../../services/paymentProviderSettings';
import {
  confirmPremiumForOrder,
  ensurePremiumActivatedForPaidOrder,
  isPaymentCompletedStatus,
  parseStartPaymentFromLegacyBody,
  pollUnifiedPaymentStatus,
  providerHealthSnapshot,
  startPaymentSuccessJson,
  startUnifiedPayment,
} from '../../services/unifiedPayments';
import {
  ensureSonicPesaConfigured,
  extractSonicWebhookPaid,
  verifySonicPesaWebhookHmac,
} from '../../services/sonicPesa';
import { PAYMENT_PROVIDERS } from '../../services/paymentProviderSettings';
import { normalizePhoneToLocal0 } from '../../lib/tzPhone';

function isZenoPaymentTerminalFailure(paymentStatus: string): boolean {
  const s = String(paymentStatus ?? '')
    .trim()
    .toUpperCase();
  return (
    s === 'FAILED' ||
    s === 'ERROR' ||
    s === 'CANCELLED' ||
    s === 'CANCELED' ||
    s === 'REJECTED' ||
    s === 'DECLINED' ||
    s === 'EXPIRED'
  );
}

/** Compare TZ national numbers across `07…`, `+255…`, `255…` shapes. */
function normalizeTzBuyerPhone(raw: string): string {
  const norm = normalizePhoneToLocal0(raw);
  if (norm.local) return norm.local;
  const d = String(raw ?? '').replace(/\D/g, '');
  if (d.length >= 9 && d.startsWith('255')) return `0${d.slice(3, 12)}`.slice(0, 10);
  if (d.length === 9) return `0${d}`.slice(0, 10);
  if (d.length >= 10 && d.startsWith('0')) return d.slice(0, 10);
  return d.slice(0, 12);
}

function paymentStatusFromZenoRow(row: Record<string, unknown> | null | undefined): string {
  if (!row || typeof row !== 'object') return '';
  const keys = [
    'payment_status',
    'PaymentStatus',
    'paymentStatus',
    'transaction_status',
    'TransactionStatus',
    'order_status',
    'OrderStatus',
    'payment_state',
    'PaymentState',
  ] as const;
  for (const k of keys) {
    const v = row[k];
    if (v == null) continue;
    const s = String(v).trim();
    if (s.length > 0) return s.toUpperCase();
  }
  return '';
}

function paymentStatusFromUnknown(payload: unknown): string {
  if (!payload || typeof payload !== 'object') return '';
  const map = payload as Record<string, unknown>;
  const direct = paymentStatusFromZenoRow(map);
  if (direct) return direct;
  for (const key of ['data', 'order', 'transaction', 'payload'] as const) {
    const nested = map[key];
    if (Array.isArray(nested) && nested.length > 0) {
      const d = paymentStatusFromUnknown(nested[0]);
      if (d) return d;
    } else if (nested != null) {
      const d = paymentStatusFromUnknown(nested);
      if (d) return d;
    }
  }
  return '';
}

export const publicRouter = Router();

function sendUpdateRequired(
  res: import('express').Response,
  appUpdate: ReturnType<typeof buildAppUpdatePayload>,
): void {
  res.status(426).json({
    ok: false,
    updateRequired: true,
    appUpdate,
    minVersion: appUpdate.minVersion,
    latestVersion: appUpdate.latestVersion,
    error: 'App update required before using Supasoka',
  });
}

publicRouter.get('/config', async (req, res, next) => {
  try {
    const [config, updateSettings] = await Promise.all([
      fetchPublicConfig(),
      fetchAppUpdateSettings(),
    ]);
    const client = readClientAppIdentity(req);
    const appUpdate = buildAppUpdatePayload(updateSettings, client);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    const catalog = appUpdate.updateRequired
      ? stripCatalogForForcedUpdate(config)
      : redactPlaybackSecretsFromConfig(config);
    const body = {
      ok: true,
      ...catalog,
      appUpdate,
      updateRequired: appUpdate.updateRequired,
      minVersion: appUpdate.minVersion,
      latestVersion: appUpdate.latestVersion,
    };
    res.json(body);
  } catch (e) {
    next(e);
  }
});

/** Lightweight update gate — always safe for older/newer app builds to poll. */
publicRouter.get('/app-update', async (req, res, next) => {
  try {
    const updateSettings = await fetchAppUpdateSettings();
    const client = readClientAppIdentity(req);
    const appUpdate = buildAppUpdatePayload(updateSettings, client);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.json({
      ok: true,
      appUpdate,
      updateRequired: appUpdate.updateRequired,
      minVersion: appUpdate.minVersion,
      latestVersion: appUpdate.latestVersion,
    });
  } catch (e) {
    next(e);
  }
});

/** Live playback session — server verifies app build + premium before returning stream URLs. */
publicRouter.get('/playback/:channelId', async (req, res, next) => {
  try {
    const channelId = Number(req.params.channelId);
    if (!Number.isFinite(channelId) || channelId <= 0) {
      res.status(400).json({ ok: false, error: 'Invalid channel id' });
      return;
    }
    const userId = String(req.query.userId ?? req.query.publicId ?? '').trim();
    const out = await resolvePlaybackForChannel(channelId, userId, req);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');

    if (!out.ok) {
      if (out.code === 'UPDATE_REQUIRED') {
        const { appUpdate } = await assertSupportedAppClient(req);
        sendUpdateRequired(res, appUpdate);
        return;
      }
      if (out.code === 'PREMIUM_REQUIRED') {
        res.status(403).json({ ok: false, premiumRequired: true, error: 'Premium subscription required' });
        return;
      }
      res.status(404).json({ ok: false, error: out.code });
      return;
    }

    res.json({ ok: true, ...out.session });
  } catch (e) {
    next(e);
  }
});

/** Lightweight viewer poll: same sync cursor as full `/config` without heavy joins. */
publicRouter.get('/config-meta', async (req, res, next) => {
  try {
    const [meta, updateSettings] = await Promise.all([
      fetchPublicConfigMeta(),
      fetchAppUpdateSettings(),
    ]);
    const client = readClientAppIdentity(req);
    const appUpdate = buildAppUpdatePayload(updateSettings, client);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.json({
      ok: true,
      ...meta,
      appUpdate,
      updateRequired: appUpdate.updateRequired,
      minVersion: appUpdate.minVersion,
      latestVersion: appUpdate.latestVersion,
    });
  } catch (e) {
    next(e);
  }
});

/** Viewer app: register stable `User-xxxxx` id on first open (and heartbeat on return). */
publicRouter.post('/register-user', async (req, res, next) => {
  try {
    await registerPublicUser(req.body);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

/** Viewer app: get premium status for a user. */
publicRouter.get('/user-premium/:userId', async (req, res, next) => {
  try {
    const userId = String(req.params.userId ?? '').trim();
    const out = await getUserPremiumRecord(userId);
    res.json({ ok: true, premiumUntilMs: out.premiumUntilMs, userExists: out.userExists });
  } catch (e) {
    next(e);
  }
});

/** Public: which gateway new checkouts use (admin toggle in SupaAdmin). */
publicRouter.get('/settings/payment-provider', async (_req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store, max-age=0');
    const paymentProvider = await getSelectedPaymentProvider();
    res.json({ ok: true, ...providerHealthSnapshot(paymentProvider) });
  } catch (e) {
    next(e);
  }
});

async function handleConfirmPremium(req: import('express').Request, res: import('express').Response, next: import('express').NextFunction) {
  try {
    const b = (req.body ?? {}) as Record<string, unknown>;
    const orderId = String(b.orderId ?? '').trim();
    const publicId = String(b.publicId ?? '').trim();
    const planId = String(b.planId ?? '').trim();
    const phone = String(b.phone ?? '').trim();

    if (!orderId || !publicId || !planId) {
      logger.warn({ orderId, publicId, planId }, 'payment_confirm_missing_fields');
      res.status(400).json({ ok: false, error: 'Missing orderId/publicId/planId' });
      return;
    }

    const out = await confirmPremiumForOrder({ orderId, publicId, planId, phone });
    logger.info({ orderId, publicId, planId, premiumUntilMs: out.premiumUntilMs }, 'payment_confirm_activated');
    res.json({ ok: true, premiumUntilMs: out.premiumUntilMs });
  } catch (e) {
    if (e && typeof e === 'object' && 'statusCode' in e) {
      const he = e as { statusCode: number; message: string };
      res.status(he.statusCode).json({ ok: false, error: he.message });
      return;
    }
    next(e);
  }
}

/**
 * Viewer app: verify payment on the server (Zeno or SonicPesa), then activate premium.
 */
publicRouter.post('/confirm-premium', handleConfirmPremium);

/** Backward-compatible alias. */
publicRouter.post('/confirm-zeno-premium', handleConfirmPremium);

async function handleUnifiedPaymentStart(
  req: import('express').Request,
  res: import('express').Response,
  next: import('express').NextFunction,
): Promise<void> {
  try {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const parsed = parseStartPaymentFromLegacyBody(body);
    if (!parsed) {
      res.status(400).json({ ok: false, error: 'Missing publicId, planId, phone, or amount' });
      return;
    }

    const out = await startUnifiedPayment(parsed);
    logger.info(
      { orderId: out.orderId, publicId: parsed.publicId, planId: parsed.planId, provider: out.provider },
      'payment_start',
    );
    res.json({ ...startPaymentSuccessJson(out), status: out.status });
  } catch (e) {
    next(e);
  }
}

/** Unified checkout — only active admin gateway (SonicPesa or ZenoPay). */
publicRouter.post('/payments/start', handleUnifiedPaymentStart);

/** Legacy Zeno path names — same unified checkout (never bypasses admin gateway). */
publicRouter.post('/zeno/create-order', handleUnifiedPaymentStart);
publicRouter.post('/create-order', handleUnifiedPaymentStart);
publicRouter.post('/payments/mobile_money_tanzania', handleUnifiedPaymentStart);

async function handleUnifiedPaymentStatus(
  req: import('express').Request,
  res: import('express').Response,
  next: import('express').NextFunction,
): Promise<void> {
  try {
    const orderId = String(req.query.orderId ?? req.query.order_id ?? '').trim();
    if (!orderId) {
      res.status(400).json({ resultcode: '400', status: 'error', message: 'orderId required' });
      return;
    }
    const out = await pollUnifiedPaymentStatus(orderId);
    const row =
      out.raw && typeof out.raw === 'object' && 'data' in (out.raw as object)
        ? (out.raw as { data: unknown[] }).data?.[0]
        : out.raw;
    res.json({
      resultcode: out.resultcode ?? (out.status === 'COMPLETED' ? '000' : '200'),
      status: out.status === 'COMPLETED' ? 'success' : 'success',
      data: row != null ? (Array.isArray((out.raw as { data?: unknown[] })?.data) ? (out.raw as { data: unknown[] }).data : [row]) : [],
      paymentStatus: out.status,
      ...(out.activated ? { activated: true, premiumUntilMs: out.premiumUntilMs ?? null } : {}),
    });
  } catch (e) {
    next(e);
  }
}

/** Unified status poll — active admin gateway only. */
publicRouter.get('/payments/status', handleUnifiedPaymentStatus);
publicRouter.get('/payments/order-status', handleUnifiedPaymentStatus);
publicRouter.get('/order-status', handleUnifiedPaymentStatus);

/** Legacy alias — same handler (no direct zenoapi.com from server when Sonic active). */
publicRouter.get('/zeno/order-status', handleUnifiedPaymentStatus);

/** Optional provider webhook callback. Activates premium server-side without waiting for client polling. */
publicRouter.post('/zeno/webhook', async (req, res, next) => {
  try {
    const b = (req.body ?? {}) as Record<string, unknown>;
    const orderId = String(b.order_id ?? b.orderId ?? b.reference ?? '').trim();
    if (!orderId) {
      res.status(400).json({ ok: false, error: 'Missing order id' });
      return;
    }
    const ps = paymentStatusFromUnknown(b);
    if (ps) {
      await updateIntentStatus({
        orderId,
        providerStatus: ps,
        providerPayload: b,
      });
    }

    if (!isPaymentCompletedStatus(ps)) {
      logger.info({ orderId, paymentStatus: ps || null }, 'payment_webhook_not_completed');
      res.json({ ok: true, received: true, activated: false, paymentStatus: ps || null });
      return;
    }

    const meta = (b.metadata ?? {}) as Record<string, unknown>;
    const publicId = String(meta.external_id ?? meta.public_id ?? b.public_id ?? '').trim();
    const planId = String(meta.plan_id ?? b.plan_id ?? '').trim();
    const phone = String(b.buyer_phone ?? meta.buyer_phone ?? '').trim();
    if (publicId && planId) {
      await upsertPendingIntent({
        orderId,
        publicId,
        planId,
        buyerPhone: phone,
        provider: PAYMENT_PROVIDERS.ZENO,
        providerPayload: b,
      });
    }

    const act = await ensurePremiumActivatedForPaidOrder(orderId, { publicId, planId, phone });
    if (!act.activated) {
      logger.warn({ orderId }, 'payment_webhook_activate_failed');
      res.json({ ok: true, received: true, activated: false, reason: 'Activation failed' });
      return;
    }
    logger.info({ orderId, publicId, planId, premiumUntilMs: act.premiumUntilMs }, 'payment_webhook_activated');
    res.json({ ok: true, received: true, activated: true, premiumUntilMs: act.premiumUntilMs ?? null });
  } catch (e) {
    next(e);
  }
});

/** SonicPesa webhook — configure in SonicPesa dashboard (same account as EaMax). */
publicRouter.post('/sonicpesa/webhook', async (req, res, next) => {
  try {
    ensureSonicPesaConfigured();
    const rawBodyString = JSON.stringify(req.body ?? {});
    const sigHeader =
      (req.headers['x-sonicpesa-signature'] as string | undefined) ??
      (req.headers['x-webhook-signature'] as string | undefined) ??
      (req.headers['x-signature'] as string | undefined);
    const signatureValid = verifySonicPesaWebhookHmac(rawBodyString, sigHeader);
    const payload = (req.body ?? {}) as Record<string, unknown>;
    const { orderId, paid } = extractSonicWebhookPaid(payload);

    if (!orderId) {
      res.status(400).json({ ok: false, error: 'Missing order reference' });
      return;
    }

    const tracked = await getIntent(orderId);

    if (process.env.SONICPESA_WEBHOOK_SECRET?.trim()) {
      if (!signatureValid) {
        res.status(401).json({ ok: false, error: 'Invalid webhook signature' });
        return;
      }
    } else if (tracked == null || tracked.activated_at_ms != null) {
      res.status(401).json({ ok: false, error: 'Webhook not verified' });
      return;
    }

    if (!paid) {
      res.json({ ok: true, received: true, activated: false });
      return;
    }

    const act = await ensurePremiumActivatedForPaidOrder(orderId, {
      publicId: tracked?.public_id ?? undefined,
      planId: tracked?.plan_id ?? undefined,
      phone: tracked?.buyer_phone ?? undefined,
    });
    if (!act.activated) {
      logger.warn({ orderId }, 'payment_sonic_webhook_activate_failed');
      res.json({ ok: true, received: true, activated: false, reason: 'Activation failed' });
      return;
    }
    logger.info(
      { orderId, publicId: tracked?.public_id, planId: tracked?.plan_id, premiumUntilMs: act.premiumUntilMs },
      'payment_webhook_activated',
    );
    res.json({ ok: true, received: true, activated: true, premiumUntilMs: act.premiumUntilMs ?? null });
  } catch (e) {
    next(e);
  }
});
