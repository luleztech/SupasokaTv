import { Router } from 'express';
import { fetchAdminExportConfig } from '../../services/adminExport';
import { importAppConfig } from '../../services/adminImport';
import { HttpError } from '../../middleware/errorHandler';
import { requireAdmin } from '../../middleware/adminAuth';
import { deleteUserById, listUsersForAdmin } from '../../services/userDirectory';
import { checkPushConfiguration, sendPushToTopic } from '../../services/pushNotifications';

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

adminRouter.get('/users', requireAdmin, async (_req, res, next) => {
  try {
    const users = await listUsersForAdmin();
    res.json({ ok: true, users });
  } catch (e) {
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
    const out = await sendPushToTopic({ title, body, target });
    res.json({ ok: true, ...out });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.toLowerCase().includes('fcm credentials missing')) {
      next(new HttpError(503, 'Push is not configured on server. Set FCM credentials env vars.', 'PUSH_NOT_CONFIGURED'));
      return;
    }
    next(new HttpError(502, `Push send failed: ${msg}`, 'PUSH_SEND_FAILED'));
  }
});

adminRouter.get('/notify-health', requireAdmin, async (_req, res, next) => {
  try {
    checkPushConfiguration();
    res.json({ ok: true, message: 'Push configuration looks valid.' });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.toLowerCase().includes('fcm credentials missing')) {
      next(new HttpError(503, 'Push is not configured on server. Set FCM credentials env vars.', 'PUSH_NOT_CONFIGURED'));
      return;
    }
    next(new HttpError(502, `Push health check failed: ${msg}`, 'PUSH_HEALTH_FAILED'));
  }
});
