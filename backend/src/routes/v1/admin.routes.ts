import { randomUUID } from 'crypto';
import { Router } from 'express';
import { getPool } from '../../db/pool';
import { fetchAdminExportConfig } from '../../services/adminExport';
import { importAppConfig } from '../../services/adminImport';
import {
  deleteChannelFast,
  deleteLiveMatchFast,
  deleteMalipoPlanFast,
  reorderChannelsFast,
  replaceCarouselFast,
  setCustomerCareWhatsappFast,
  upsertChannelFast,
  upsertLiveMatchFast,
  upsertMalipoPlanFast,
} from '../../services/adminCatalog';
import { importAppUpdateSettings } from '../../services/appUpdateSettingsImport';
import { HttpError } from '../../middleware/errorHandler';
import { requireAdmin } from '../../middleware/adminAuth';
import { applyAdminPremiumUpdate, deleteUserById, isValidPublicUserId, listUsersForAdmin } from '../../services/userDirectory';
import {
  checkEamaxBridgeConfiguration,
  mirrorPushToEamax,
} from '../../services/eamaxPushBridge';
import { checkPushConfiguration, sendPushToTopic, sendPushToUser } from '../../services/pushNotifications';
import {
  getSelectedPaymentProvider,
  isSonicPesaConfigured,
  PAYMENT_PROVIDERS,
  setPaymentProvider,
} from '../../services/paymentProviderSettings';
import { providerHealthSnapshot } from '../../services/unifiedPayments';
import { revokeAllActivePremium, revokePremiumWithoutVerifiedPayment } from '../../services/premiumCleanup';
import { fetchPaymentHealth } from '../../services/paymentHealth';

export const adminRouter = Router();

/** Full config from Postgres (channels, users, etc.) — SupaAdmin should load this on startup. */
adminRouter.get('/export', requireAdmin, async (_req, res, next) => {
  try {
    const config = await fetchAdminExportConfig();
    res.json({ ok: true, ...config });
  } catch (e) {
    next(e);
  }
});

adminRouter.post('/import', requireAdmin, async (req, res, next) => {
  try {
    await importAppConfig(req.body);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/channels/:id', requireAdmin, async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const body = { ...(req.body as Record<string, unknown>), id };
    await upsertChannelFast(body);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

adminRouter.post('/channels', requireAdmin, async (req, res, next) => {
  try {
    await upsertChannelFast(req.body);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

adminRouter.delete('/channels/:id', requireAdmin, async (req, res, next) => {
  try {
    const deleted = await deleteChannelFast(Number(req.params.id));
    res.json({ ok: true, deleted });
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/channels/reorder', requireAdmin, async (req, res, next) => {
  try {
    const ids = (req.body as { ids?: unknown })?.ids;
    if (!Array.isArray(ids)) {
      res.status(400).json({ ok: false, error: 'ids array required' });
      return;
    }
    await reorderChannelsFast(ids.map((x) => Number(x)).filter((n) => Number.isFinite(n)));
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/carousel', requireAdmin, async (req, res, next) => {
  try {
    const slides = (req.body as { slides?: unknown })?.slides;
    await replaceCarouselFast(Array.isArray(slides) ? slides : []);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/malipo-plans/:id', requireAdmin, async (req, res, next) => {
  try {
    const id = String(req.params.id ?? '').trim();
    const body = { ...(req.body as Record<string, unknown>), id };
    await upsertMalipoPlanFast(body);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

adminRouter.delete('/malipo-plans/:id', requireAdmin, async (req, res, next) => {
  try {
    const deleted = await deleteMalipoPlanFast(String(req.params.id ?? ''));
    res.json({ ok: true, deleted });
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/live-matches/:id', requireAdmin, async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const body = { ...(req.body as Record<string, unknown>), id };
    await upsertLiveMatchFast(body);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

adminRouter.delete('/live-matches/:id', requireAdmin, async (req, res, next) => {
  try {
    const deleted = await deleteLiveMatchFast(Number(req.params.id));
    res.json({ ok: true, deleted });
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/settings/customer-care', requireAdmin, async (req, res, next) => {
  try {
    const raw = (req.body as { customerCareWhatsapp?: unknown })?.customerCareWhatsapp;
    await setCustomerCareWhatsappFast(raw);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

/** Fast settings save — app update policy only (no full catalog re-import). */
async function handleAppUpdateSettingsSave(
  req: import('express').Request,
  res: import('express').Response,
  next: import('express').NextFunction,
): Promise<void> {
  try {
    const b = (req.body ?? {}) as Record<string, unknown>;
    await importAppUpdateSettings({
      forceUpdateEnabled: b.forceUpdateEnabled === true,
      minAndroidBuild: Number(b.minAndroidBuild),
      minAndroidVersion: String(b.minAndroidVersion ?? ''),
      latestAndroidVersion: String(b.latestAndroidVersion ?? ''),
      latestAndroidBuild: Number(b.latestAndroidBuild),
      playStoreUrl: String(b.playStoreUrl ?? ''),
    });
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
}

adminRouter.put('/settings/app-update', requireAdmin, handleAppUpdateSettingsSave);
adminRouter.post('/settings/app-update', requireAdmin, handleAppUpdateSettingsSave);

adminRouter.get('/users', requireAdmin, async (_req, res, next) => {
  try {
    const users = await listUsersForAdmin();
    res.json({ ok: true, users });
  } catch (e) {
    next(e);
  }
});

adminRouter.get('/settings/payment-provider', requireAdmin, async (_req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store, max-age=0');
    await getSelectedPaymentProvider();
    res.json({ ok: true, ...providerHealthSnapshot() });
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/settings/payment-provider', requireAdmin, async (_req, res, next) => {
  try {
    if (!isSonicPesaConfigured()) {
      res.status(400).json({
        ok: false,
        error: {
          message:
            'SonicPesa haijasanidi: weka SONICPESA_API_KEY (na SONICPESA_SECRET_KEY ikiwa inahitajika) kwenye Railway — tumia thamani sawa na EaMax.',
          code: 'SONIC_NOT_CONFIGURED',
        },
        paymentProvider: PAYMENT_PROVIDERS.SONICPESA,
        configured: false,
      });
      return;
    }
    await setPaymentProvider(PAYMENT_PROVIDERS.SONICPESA);
    res.json({ ok: true, paymentProvider: PAYMENT_PROVIDERS.SONICPESA, configured: true });
  } catch (e) {
    next(e);
  }
});

adminRouter.get('/payment-health', requireAdmin, async (_req, res, next) => {
  try {
    const pool = getPool();
    if (!pool) {
      throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
    }

    const { summary, recent, dailyRevenue, revenueTodayDay } = await fetchPaymentHealth(pool);

    res.json({
      ok: true,
      summary,
      recent,
      dailyRevenue,
      revenueTodayDay,
      revenueTimezone: 'Africa/Dar_es_Salaam',
      updatedAtMs: Date.now(),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.toLowerCase().includes('relation "payment_intents" does not exist')) {
      next(new HttpError(503, 'payment_intents table is missing. Run migrations first.', 'PAYMENT_TABLE_MISSING'));
      return;
    }
    next(e);
  }
});

adminRouter.delete('/users/:id', requireAdmin, async (req, res, next) => {
  try {
    const ok = await deleteUserById(String(req.params.id ?? ''));
    res.json({ ok: true, deleted: ok });
  } catch (e) {
    next(e);
  }
});

adminRouter.put('/users/:id/premium', requireAdmin, async (req, res, next) => {
  try {
    const userId = String(req.params.id ?? '').trim();
    if (!userId) {
      res.status(400).json({ ok: false, error: 'user id is required' });
      return;
    }
    const b = (req.body ?? {}) as Record<string, unknown>;
    const raw = b.premiumUntilMs;
    let premiumUntilMs: number | null = null;
    if (raw !== null && raw !== undefined && raw.toString().trim().length > 0) {
      const n = Number(raw);
      if (!Number.isFinite(n) || n < 0) {
        res.status(400).json({ ok: false, error: 'premiumUntilMs must be null or a valid timestamp' });
        return;
      }
      premiumUntilMs = Math.trunc(n);
    }
    const updated = await applyAdminPremiumUpdate(userId, premiumUntilMs);
    if (!updated) {
      res.status(404).json({ ok: false, error: 'user not found' });
      return;
    }
    const effectiveMs =
      premiumUntilMs == null
        ? Date.now()
        : premiumUntilMs;
    res.json({ ok: true, userId, premiumUntilMs: effectiveMs });
  } catch (e) {
    next(e);
  }
});

/** Revoke active premium for users with no verified payment on record (system mistake cleanup). */
adminRouter.post('/maintenance/revoke-mistaken-premium', requireAdmin, async (_req, res, next) => {
  try {
    const out = await revokePremiumWithoutVerifiedPayment();
    res.json({ ok: true, ...out });
  } catch (e) {
    next(e);
  }
});

/**
 * Revoke active premium for EVERY user, including ones with a verified
 * payment. Irreversible bulk action — only ever triggered from an explicit,
 * typed-confirmation admin action.
 */
adminRouter.post('/maintenance/revoke-all-premium', requireAdmin, async (_req, res, next) => {
  try {
    const out = await revokeAllActivePremium();
    res.json({ ok: true, ...out });
  } catch (e) {
    next(e);
  }
});

adminRouter.post('/notify', requireAdmin, async (req, res, next) => {
  try {
    const b = (req.body ?? {}) as Record<string, unknown>;
    const title = String(b.title ?? '').trim();
    const body = String(b.body ?? '').trim();
    const target = String(b.target ?? 'all').trim();
    if (!title) {
      res.status(400).json({ ok: false, error: 'title is required' });
      return;
    }
    const [out, eamaxMirror] = await Promise.all([
      sendPushToTopic({ title, body, target }),
      mirrorPushToEamax({ title, body, scope: 'broadcast', target }),
    ]);
    const pool = getPool();
    let savedNotification: Record<string, unknown> | null = null;
    let notificationPersistError: string | undefined;
    if (pool) {
      try {
        const id = randomUUID();
        const saved = await pool.query(
          `INSERT INTO notifications (id, title, body, target, created_at)
           VALUES ($1, $2, $3, $4, now())
           RETURNING id, title, body, target, created_at AS "createdAt", scheduled_for AS "scheduledFor"`,
          [id, title, body, target || 'all'],
        );
        const row = saved.rows[0] as Record<string, unknown> | undefined;
        if (row != null) {
          savedNotification = row;
        }
      } catch (dbErr) {
        const dm = dbErr instanceof Error ? dbErr.message : String(dbErr);
        notificationPersistError = dm;
      }
    }
    res.json({
      ok: true,
      ...out,
      eamaxMirror,
      notification: savedNotification,
      ...(notificationPersistError ? { notificationPersistError } : {}),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.toLowerCase().includes('fcm credentials missing')) {
      next(new HttpError(503, 'Push is not configured on server. Set FCM credentials env vars.', 'PUSH_NOT_CONFIGURED'));
      return;
    }
    next(new HttpError(502, `Push send failed: ${msg}`, 'PUSH_SEND_FAILED'));
  }
});

adminRouter.delete('/notifications', requireAdmin, async (_req, res, next) => {
  try {
    const pool = getPool();
    if (!pool) {
      throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
    }
    const out = await pool.query(`DELETE FROM notifications`);
    res.json({ ok: true, deleted: out.rowCount ?? 0 });
  } catch (e) {
    next(e);
  }
});

adminRouter.delete('/notifications/:id', requireAdmin, async (req, res, next) => {
  try {
    const pool = getPool();
    if (!pool) {
      throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
    }
    const idRaw = String(req.params.id ?? '').trim();
    if (!idRaw) {
      throw new HttpError(400, 'Notification id is required', 'BAD_NOTIFICATION_ID');
    }
    const out = await pool.query(`DELETE FROM notifications WHERE id = $1`, [idRaw]);
    res.json({ ok: true, deleted: (out.rowCount ?? 0) > 0 });
  } catch (e) {
    next(e);
  }
});

adminRouter.get('/notify-health', requireAdmin, async (_req, res, next) => {
  try {
    checkPushConfiguration();
    const eamaxBridge = checkEamaxBridgeConfiguration();
    res.json({
      ok: true,
      message: 'Push configuration looks valid.',
      eamaxBridge,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.toLowerCase().includes('fcm credentials missing')) {
      next(new HttpError(503, 'Push is not configured on server. Set FCM credentials env vars.', 'PUSH_NOT_CONFIGURED'));
      return;
    }
    next(new HttpError(502, `Push health check failed: ${msg}`, 'PUSH_HEALTH_FAILED'));
  }
});

const defaultExpiredTitle = 'Kifurushi chako kimeisha';
const defaultExpiredBody =
  'Mpendwa mteja, kifurushi chako kimeisha muda wake. Tafadhali lipia uendelee kufurahia vipindi vyetu bora sana.';

adminRouter.post('/notify-user/:id', requireAdmin, async (req, res, next) => {
  try {
    const publicId = decodeURIComponent(String(req.params.id ?? '').trim());
    const b = (req.body ?? {}) as Record<string, unknown>;
    const title = String(b.title ?? '').trim();
    const body = String(b.body ?? '').trim();
    if (!publicId) {
      res.status(400).json({ ok: false, error: 'publicId is required' });
      return;
    }
    if (!isValidPublicUserId(publicId)) {
      res.status(400).json({
        ok: false,
        error: 'publicId must match User-XXXXX (5 chars A–Z, a–z, 2–9)',
      });
      return;
    }
    if (!title) {
      res.status(400).json({ ok: false, error: 'title is required' });
      return;
    }

    const out = await sendPushToUser({ publicId, title, body });
    const eamaxMirror = await mirrorPushToEamax({
      title,
      body,
      scope: 'user',
      externalId: publicId,
    });
    const pool = getPool();
    let savedNotification: Record<string, unknown> | null = null;
    let notificationPersistError: string | undefined;
    if (pool) {
      try {
        const id = randomUUID();
        const saved = await pool.query(
          `INSERT INTO notifications (id, title, body, target, created_at)
           VALUES ($1, $2, $3, $4, now())
           RETURNING id, title, body, target, created_at AS "createdAt", scheduled_for AS "scheduledFor"`,
          [id, title, body, `user:${publicId}`],
        );
        const row = saved.rows[0] as Record<string, unknown> | undefined;
        if (row != null) savedNotification = row;
      } catch (dbErr) {
        const dm = dbErr instanceof Error ? dbErr.message : String(dbErr);
        notificationPersistError = dm;
      }
    }
    res.json({
      ok: true,
      ...out,
      eamaxMirror,
      notification: savedNotification,
      ...(notificationPersistError ? { notificationPersistError } : {}),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    next(new HttpError(502, `Push send failed: ${msg}`, 'PUSH_SEND_FAILED'));
  }
});

/** Targeted reminders for many viewers (e.g. all expired) — one FCM send per id. */
adminRouter.post('/notify-expired-batch', requireAdmin, async (req, res, next) => {
  try {
    const b = (req.body ?? {}) as Record<string, unknown>;
    const rawIds = b.ids;
    const title = String(b.title ?? defaultExpiredTitle).trim() || defaultExpiredTitle;
    const bodyText = String(b.body ?? defaultExpiredBody).trim() || defaultExpiredBody;

    if (!Array.isArray(rawIds) || rawIds.length === 0) {
      res.status(400).json({ ok: false, error: 'ids must be a non-empty array of public ids' });
      return;
    }

    const pool = getPool();
    type RowResult = {
      id: string;
      ok: boolean;
      messageId?: string;
      error?: string;
      eamaxMirror?: Awaited<ReturnType<typeof mirrorPushToEamax>>;
    };
    const results: RowResult[] = [];
    let notificationPersistErrors = 0;

    for (const raw of rawIds) {
      const publicId = String(raw ?? '').trim();
      if (!isValidPublicUserId(publicId)) {
        results.push({ id: publicId, ok: false, error: 'invalid public id format' });
        continue;
      }
      try {
        const [out, eamaxMirror] = await Promise.all([
          sendPushToUser({ publicId, title, body: bodyText }),
          mirrorPushToEamax({
            title,
            body: bodyText,
            scope: 'user',
            externalId: publicId,
          }),
        ]);
        results.push({
          id: publicId,
          ok: true,
          messageId: out.messageId,
          eamaxMirror,
        });
        if (pool) {
          try {
            const nid = randomUUID();
            await pool.query(
              `INSERT INTO notifications (id, title, body, target, created_at)
               VALUES ($1, $2, $3, $4, now())`,
              [nid, title, bodyText, `user:${publicId}`],
            );
          } catch (_dbErr) {
            notificationPersistErrors += 1;
          }
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        results.push({ id: publicId, ok: false, error: msg });
      }
    }

    const sent = results.filter((r) => r.ok).length;
    const failed = results.filter((r) => !r.ok).length;

    res.json({
      ok: true,
      sent,
      failed,
      results,
      ...(notificationPersistErrors > 0
        ? {
            notificationPersistError: `${notificationPersistErrors} notification row(s) failed to save`,
          }
        : {}),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.toLowerCase().includes('fcm credentials missing')) {
      next(new HttpError(503, 'Push is not configured on server. Set FCM credentials env vars.', 'PUSH_NOT_CONFIGURED'));
      return;
    }
    next(new HttpError(502, `Batch push failed: ${msg}`, 'PUSH_BATCH_FAILED'));
  }
});
