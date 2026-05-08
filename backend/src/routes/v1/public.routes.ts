import { Router } from 'express';
import { fetchPublicConfig, fetchPublicConfigMeta } from '../../services/publicConfig';
import { registerPublicUser, getUserPremiumStatus } from '../../services/userDirectory';
import { createZenoOrder, fetchZenoOrderStatus } from '../../services/zenoPay';
import { activatePremiumForUser } from '../../services/premiumActivation';
import {
  getIntent,
  markIntentActivated,
  upsertPendingIntent,
  updateIntentStatus,
} from '../../services/paymentIntents';

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

/**
 * Viewer app: verify a Zeno order on the server (protects against spoofed client success),
 * then activate premium in DB so SupaAdmin + other devices can see it.
 */
publicRouter.post('/confirm-zeno-premium', async (req, res, next) => {
  try {
    const b = (req.body ?? {}) as Record<string, unknown>;
    const orderId = String(b.orderId ?? '').trim();
    const publicId = String(b.publicId ?? '').trim();
    const planId = String(b.planId ?? '').trim();
    const phone = String(b.phone ?? '').trim();

    if (!orderId || !publicId || !planId) {
      res.status(400).json({ ok: false, error: 'Missing orderId/publicId/planId' });
      return;
    }

    const tracked = await getIntent(orderId);
    if (tracked?.public_id && tracked.public_id !== publicId) {
      res.status(409).json({ ok: false, error: 'Order belongs to another user' });
      return;
    }
    if (tracked?.plan_id && tracked.plan_id !== planId) {
      res.status(409).json({ ok: false, error: 'Order does not match selected plan' });
      return;
    }
    if (tracked?.activated_at_ms != null) {
      const until = await getUserPremiumStatus(publicId);
      res.json({ ok: true, premiumUntilMs: until });
      return;
    }

    const row = await fetchZenoOrderStatus(orderId);
    const ps = paymentStatusFromZenoRow(row as Record<string, unknown> | null);
    if (ps) {
      await updateIntentStatus({
        orderId,
        providerStatus: ps,
        providerPayload: row ?? null,
      });
    }
    if (!isZenoPaymentCompleted(ps)) {
      const code = isZenoPaymentTerminalFailure(ps) ? 409 : 402;
      res.status(code).json({ ok: false, error: 'Payment not completed', paymentStatus: ps || null });
      return;
    }

    // Basic phone cross-check when available.
    const zPhone = String((row as any)?.buyer_phone ?? '').trim();
    if (phone && zPhone) {
      const a = normalizeTzBuyerPhone(phone);
      const zNorm = normalizeTzBuyerPhone(zPhone);
      if (a.length >= 9 && zNorm.length >= 9 && a !== zNorm) {
        res.status(409).json({ ok: false, error: 'Phone mismatch' });
        return;
      }
    }

    const activated = await activatePremiumForUser({
      publicId,
      planId,
      phone,
      note: `zeno:${orderId}`,
    });
    await markIntentActivated(orderId);

    res.json({ ok: true, premiumUntilMs: activated.premiumUntilMs });
  } catch (e) {
    next(e);
  }
});

/** Viewer app: backend-proxied Zeno create-order (uses server env `ZENO_API_KEY`). */
publicRouter.post('/zeno/create-order', async (req, res, next) => {
  try {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const out = await createZenoOrder(body);
    const orderId = String(out.order_id ?? out.orderId ?? '').trim();
    if (orderId) {
      const metadata = (body.metadata ?? {}) as Record<string, unknown>;
      await upsertPendingIntent({
        orderId,
        publicId: String(metadata.external_id ?? metadata.public_id ?? '').trim(),
        planId: String(metadata.plan_id ?? '').trim(),
        amountTzs: Number(body.amount ?? 0),
        buyerPhone: String(body.buyer_phone ?? metadata.buyer_phone ?? '').trim(),
        providerPayload: out,
      });
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
      res.json({ ok: true, received: true, activated: false, paymentStatus: ps || null });
      return;
    }

    const tracked = await getIntent(orderId);
    if (!tracked || !tracked.public_id || !tracked.plan_id) {
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
      note: `zeno:${orderId}`,
    });
    await markIntentActivated(orderId);
    res.json({ ok: true, received: true, activated: true });
  } catch (e) {
    next(e);
  }
});

/** Viewer app: backend-proxied Zeno order-status (uses server env `ZENO_API_KEY`). */
publicRouter.get('/zeno/order-status', async (req, res, next) => {
  try {
    const orderId = String(req.query.order_id ?? '').trim();
    if (!orderId) {
      res.status(400).json({ resultcode: '400', status: 'error', message: 'order_id is required' });
      return;
    }
    const local = await getIntent(orderId);
    if (local?.activated_at_ms != null || local?.status === 'COMPLETED') {
      res.json({
        resultcode: '000',
        status: 'success',
        data: [{ payment_status: 'COMPLETED', order_id: orderId }],
      });
      return;
    }

    const row = await fetchZenoOrderStatus(orderId);
    const ps = paymentStatusFromZenoRow(row as Record<string, unknown> | null);
    if (ps) {
      await updateIntentStatus({
        orderId,
        providerStatus: ps,
        providerPayload: row ?? null,
      });
    }
    res.json({
      resultcode: row ? '000' : '404',
      status: row ? 'success' : 'error',
      data: row ? [row] : [],
    });
  } catch (e) {
    next(e);
  }
});
