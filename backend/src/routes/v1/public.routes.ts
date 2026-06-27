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
} from '../../services/paymentIntents';
import { getSelectedPaymentProvider } from '../../services/paymentProviderSettings';
import {
  confirmPremiumForOrder,
  ensurePremiumActivatedForPaidOrder,
  parseStartPaymentFromLegacyBody,
  pollUnifiedPaymentStatus,
  providerHealthSnapshot,
  reconcilePremiumForUser,
  startPaymentSuccessJson,
  startUnifiedPayment,
} from '../../services/unifiedPayments';
import {
  ensureSonicPesaConfigured,
  extractSonicWebhookPaid,
  verifySonicPesaWebhookHmac,
} from '../../services/sonicPesa';

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

/** Viewer app: get premium status for a user (read-only — never re-grant here). */
publicRouter.get('/user-premium/:userId', async (req, res, next) => {
  try {
    const userId = String(req.params.userId ?? '').trim();
    const out = await getUserPremiumRecord(userId);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.json({ ok: true, premiumUntilMs: out.premiumUntilMs, userExists: out.userExists });
  } catch (e) {
    next(e);
  }
});

/** Public: SonicPesa gateway health for the mobile app. */
publicRouter.get('/settings/payment-provider', async (_req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store, max-age=0');
    await getSelectedPaymentProvider();
    res.json({ ok: true, ...providerHealthSnapshot() });
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
 * Viewer app: verify SonicPesa payment on the server, then activate premium.
 */
publicRouter.post('/confirm-premium', handleConfirmPremium);

/** Backward-compatible alias for older app builds. */
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

/** SonicPesa checkout — all mobile money networks (M-Pesa, Tigo/Yas, Airtel, Halopesa). */
publicRouter.post('/payments/start', handleUnifiedPaymentStart);

/** Legacy path aliases — all route to SonicPesa checkout. */
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

/** Payment status poll — SonicPesa order status. */
publicRouter.get('/payments/status', handleUnifiedPaymentStatus);
publicRouter.get('/payments/order-status', handleUnifiedPaymentStatus);
publicRouter.get('/order-status', handleUnifiedPaymentStatus);
publicRouter.get('/zeno/order-status', handleUnifiedPaymentStatus);

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
