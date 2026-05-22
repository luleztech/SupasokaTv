import { Router } from 'express';
import { fetchPublicConfig, fetchPublicConfigMeta } from '../../services/publicConfig';
import { registerPublicUser, getUserPremiumStatus } from '../../services/userDirectory';
import { createZenoOrder, fetchZenoOrderStatus } from '../../services/zenoPay';
import { activatePremiumForUser } from '../../services/premiumActivation';
import { logger } from '../../lib/logger';
import {
  getIntent,
  markIntentActivated,
  upsertPendingIntent,
  updateIntentStatus,
} from '../../services/paymentIntents';
import { getSelectedPaymentProvider } from '../../services/paymentProviderSettings';
import {
  confirmPremiumForOrder,
  pollUnifiedPaymentStatus,
  providerHealthSnapshot,
  startUnifiedPayment,
} from '../../services/unifiedPayments';
import {
  ensureSonicPesaConfigured,
  extractSonicWebhookPaid,
  verifySonicPesaWebhookHmac,
} from '../../services/sonicPesa';
import { PAYMENT_PROVIDERS } from '../../services/paymentProviderSettings';

function isZenoPaymentCompleted(paymentStatus: string): boolean {
  const s = String(paymentStatus ?? '')
    .trim()
    .toUpperCase();
  return (
    s === 'COMPLETED' ||
    s === 'COMPLETE' ||
    s === 'SUCCESS' ||
    s === 'SUCCESSFUL' ||
    s === 'SUCCEEDED' ||
    s === 'PAID' ||
    s === 'APPROVED' ||
    s === 'AUTHORIZED' ||
    s === 'AUTHORISED' ||
    s === 'SETTLED'
  );
}

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
  const d = String(raw ?? '').replace(/\D/g, '');
  if (d.length >= 9 && d.startsWith('255')) {
    return `0${d.slice(3, 12)}`.slice(0, 10);
  }
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

publicRouter.get('/config', async (_req, res, next) => {
  try {
    const config = await fetchPublicConfig();
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.json({ ok: true, ...config });
  } catch (e) {
    next(e);
  }
});

/** Lightweight viewer poll: same sync cursor as full `/config` without heavy joins. */
publicRouter.get('/config-meta', async (_req, res, next) => {
  try {
    const meta = await fetchPublicConfigMeta();
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.json({ ok: true, ...meta });
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
    const premiumUntilMs = await getUserPremiumStatus(userId);
    res.json({ ok: true, premiumUntilMs });
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

/** Unified checkout — respects SupaAdmin payment_provider (SonicPesa or ZenoPay). */
publicRouter.post('/payments/start', async (req, res, next) => {
  try {
    const b = (req.body ?? {}) as Record<string, unknown>;
    const metadata = (b.metadata ?? {}) as Record<string, unknown>;
    const publicId = String(
      b.publicId ?? b.externalId ?? metadata.external_id ?? metadata.public_id ?? '',
    ).trim();
    const planId = String(b.planId ?? b.bundle ?? metadata.plan_id ?? '').trim();
    const phone = String(b.phone ?? b.buyer_phone ?? metadata.buyer_phone ?? '').trim();
    const amountTzs = Number(b.amount ?? b.amountTzs ?? 0);
    const orderId = String(b.order_id ?? b.orderId ?? '').trim();

    if (!publicId || !planId || !phone || amountTzs < 1) {
      res.status(400).json({ ok: false, error: 'Missing publicId, planId, phone, or amount' });
      return;
    }

    const out = await startUnifiedPayment({
      orderId: orderId || undefined,
      publicId,
      planId,
      amountTzs,
      phone,
      buyerName: String(b.buyer_name ?? b.buyerName ?? publicId).trim(),
      buyerEmail: String(b.buyer_email ?? b.buyerEmail ?? `${publicId}@supasoka.app`).trim(),
    });

    res.json({
      ok: true,
      status: out.status,
      order_id: out.orderId,
      orderId: out.orderId,
      message: out.message,
      provider: out.provider,
      resultcode: '000',
    });
  } catch (e) {
    next(e);
  }
});

/** Unified status poll — routes by payment_intents.payment_provider. */
publicRouter.get('/payments/status', async (req, res, next) => {
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
});

/** Viewer app: create-order — uses admin-selected provider (SonicPesa or ZenoPay). */
publicRouter.post('/zeno/create-order', async (req, res, next) => {
  try {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const metadata = (body.metadata ?? {}) as Record<string, unknown>;
    const publicId = String(metadata.external_id ?? metadata.public_id ?? '').trim();
    const planId = String(metadata.plan_id ?? '').trim();
    const phone = String(body.buyer_phone ?? metadata.buyer_phone ?? '').trim();
    const amountTzs = Number(body.amount ?? 0);
    const requestedOrderId = String(body.order_id ?? body.orderId ?? '').trim();

    if (publicId && planId && phone && amountTzs >= 1) {
      const out = await startUnifiedPayment({
        orderId: requestedOrderId || undefined,
        publicId,
        planId,
        amountTzs,
        phone,
        buyerName: String(body.buyer_name ?? publicId).trim(),
        buyerEmail: String(body.buyer_email ?? `${publicId}@supasoka.app`).trim(),
      });
      res.json({
        status: 'success',
        resultcode: '000',
        order_id: out.orderId,
        orderId: out.orderId,
        message: out.message,
        provider: out.provider,
      });
      return;
    }

    const activeProvider = await getSelectedPaymentProvider();
    if (activeProvider === PAYMENT_PROVIDERS.SONICPESA) {
      res.status(400).json({
        ok: false,
        error:
          'SonicPesa imewashwa na admin. Tumia /api/v1/public/payments/start na publicId, planId, phone.',
      });
      return;
    }

    const out = await createZenoOrder(body);
    const orderId = String(out.order_id ?? out.orderId ?? '').trim();
    if (orderId) {
      await upsertPendingIntent({
        orderId,
        publicId,
        planId,
        amountTzs,
        buyerPhone: phone,
        provider: PAYMENT_PROVIDERS.ZENO,
        providerPayload: out,
      });
      logger.info({ orderId, publicId, planId, amountTzs }, 'payment_order_created');
    }
    res.json(out);
  } catch (e) {
    next(e);
  }
});

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

    if (!isZenoPaymentCompleted(ps)) {
      logger.info({ orderId, paymentStatus: ps || null }, 'payment_webhook_not_completed');
      res.json({ ok: true, received: true, activated: false, paymentStatus: ps || null });
      return;
    }

    const tracked = await getIntent(orderId);
    if (!tracked || !tracked.public_id || !tracked.plan_id) {
      logger.warn({ orderId }, 'payment_webhook_intent_missing_metadata');
      res.json({ ok: true, received: true, activated: false, reason: 'Intent metadata missing' });
      return;
    }
    if (tracked.activated_at_ms != null) {
      logger.info({ orderId, publicId: tracked.public_id, planId: tracked.plan_id }, 'payment_webhook_idempotent_hit');
      res.json({ ok: true, received: true, activated: true, already: true });
      return;
    }

    await activatePremiumForUser({
      publicId: tracked.public_id,
      planId: tracked.plan_id,
      phone: tracked.buyer_phone ?? '',
      note: `zeno:${orderId}`,
    });
    await markIntentActivated(orderId);
    logger.info({ orderId, publicId: tracked.public_id, planId: tracked.plan_id }, 'payment_webhook_activated');
    res.json({ ok: true, received: true, activated: true });
  } catch (e) {
    next(e);
  }
});

/** Viewer app: order-status — SonicPesa or ZenoPay based on stored provider. */
publicRouter.get('/zeno/order-status', async (req, res, next) => {
  try {
    const orderId = String(req.query.order_id ?? req.query.orderId ?? '').trim();
    if (!orderId) {
      res.status(400).json({ resultcode: '400', status: 'error', message: 'order_id is required' });
      return;
    }
    const out = await pollUnifiedPaymentStatus(orderId);
    const data =
      out.raw && typeof out.raw === 'object' && Array.isArray((out.raw as { data?: unknown[] }).data)
        ? (out.raw as { data: unknown[] }).data
        : out.status
          ? [{ payment_status: out.status, order_id: orderId }]
          : [];
    logger.info({ orderId, paymentStatus: out.status }, 'payment_status_polled');
    res.json({
      resultcode: out.resultcode ?? '000',
      status: 'success',
      data,
    });
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
    const hasPendingSonic =
      tracked != null &&
      tracked.payment_provider === PAYMENT_PROVIDERS.SONICPESA &&
      tracked.activated_at_ms == null;

    if (process.env.SONICPESA_WEBHOOK_SECRET?.trim()) {
      if (!signatureValid) {
        res.status(401).json({ ok: false, error: 'Invalid webhook signature' });
        return;
      }
    } else if (!hasPendingSonic) {
      res.status(401).json({ ok: false, error: 'Webhook not verified' });
      return;
    }

    if (!paid) {
      res.json({ ok: true, received: true, activated: false });
      return;
    }

    if (!tracked?.public_id || !tracked.plan_id) {
      res.json({ ok: true, received: true, activated: false, reason: 'Intent metadata missing' });
      return;
    }
    if (tracked.activated_at_ms != null) {
      res.json({ ok: true, received: true, activated: true, already: true });
      return;
    }

    await activatePremiumForUser({
      publicId: tracked.public_id,
      planId: tracked.plan_id,
      phone: tracked.buyer_phone ?? '',
      note: `sonicpesa:${orderId}`,
    });
    await markIntentActivated(orderId);
    logger.info({ orderId, publicId: tracked.public_id, planId: tracked.plan_id }, 'payment_webhook_activated');
    res.json({ ok: true, received: true, activated: true });
  } catch (e) {
    next(e);
  }
});
