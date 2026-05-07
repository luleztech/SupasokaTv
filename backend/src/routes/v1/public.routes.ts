import { Router } from 'express';
import { fetchPublicConfig, fetchPublicConfigMeta } from '../../services/publicConfig';
import { registerPublicUser, getUserPremiumStatus } from '../../services/userDirectory';
import { createZenoOrder, fetchZenoOrderStatus } from '../../services/zenoPay';
import { activatePremiumForUser } from '../../services/premiumActivation';

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

    const row = await fetchZenoOrderStatus(orderId);
    const ps = String(row?.payment_status ?? '').toUpperCase();
    if (ps !== 'COMPLETED') {
      res.status(402).json({ ok: false, error: 'Payment not completed', paymentStatus: ps || null });
      return;
    }

    // Basic phone cross-check when available.
    const zPhone = String((row as any)?.buyer_phone ?? '').trim();
    if (phone && zPhone && phone !== zPhone) {
      res.status(409).json({ ok: false, error: 'Phone mismatch' });
      return;
    }

    const activated = await activatePremiumForUser({
      publicId,
      planId,
      phone,
      note: `zeno:${orderId}`,
    });

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
    res.json(out);
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
    const row = await fetchZenoOrderStatus(orderId);
    res.json({
      resultcode: row ? '000' : '404',
      status: row ? 'success' : 'error',
      data: row ? [row] : [],
    });
  } catch (e) {
    next(e);
  }
});
