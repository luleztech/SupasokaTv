import { Router } from 'express';
import { getPool } from '../../db/pool';
import { fetchAdminExportConfig } from '../../services/adminExport';
import { importAppConfig } from '../../services/adminImport';
import { HttpError } from '../../middleware/errorHandler';
import { requireAdmin } from '../../middleware/adminAuth';
import { deleteUserById, listUsersForAdmin } from '../../services/userDirectory';
import { checkPushConfiguration, sendPushToTopic, sendPushToUser } from '../../services/pushNotifications';

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
    const pool = getPool();
    let savedNotification: Record<string, unknown> | null = null;
    if (pool) {
      const saved = await pool.query(
        `INSERT INTO notifications (title, body, target, created_at)
         VALUES ($1, $2, $3, now())
         RETURNING id, title, body, target, created_at AS "createdAt", scheduled_for AS "scheduledFor"`,
        [title, body, target || 'all'],
      );
      const row = saved.rows[0] as Record<string, unknown> | undefined;
      if (row != null) {
        savedNotification = row;
      }
    }
    res.json({ ok: true, ...out, notification: savedNotification });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.toLowerCase().includes('fcm credentials missing')) {
      next(new HttpError(503, 'Push is not configured on server. Set FCM credentials env vars.', 'PUSH_NOT_CONFIGURED'));
      return;
    }
    next(new HttpError(502, `Push send failed: ${msg}`, 'PUSH_SEND_FAILED'));
  }
});

adminRouter.delete('/notifications/:id', requireAdmin, async (req, res, next) => {
  try {
    const pool = getPool();
    if (!pool) {
      throw new HttpError(503, 'DATABASE_URL is not configured', 'NO_DATABASE');
    }
    const idRaw = Number.parseInt(String(req.params.id ?? ''), 10);
    if (!Number.isFinite(idRaw) || idRaw <= 0) {
      throw new HttpError(400, 'Notification id must be a positive integer', 'BAD_NOTIFICATION_ID');
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

adminRouter.post('/notify-user/:id', requireAdmin, async (req, res, next) => {
  try {
    const publicId = String(req.params.id ?? '').trim();
    const b = (req.body ?? {}) as Record<string, unknown>;
    const title = String(b.title ?? '').trim();
    const body = String(b.body ?? '').trim();
    if (!publicId) {
      res.status(400).json({ ok: false, error: 'publicId is required' });
      return;
    }
    if (!title) {
      res.status(400).json({ ok: false, error: 'title is required' });
      return;
    }

    const out = await sendPushToUser({ publicId, title, body });
    const pool = getPool();
    let savedNotification: Record<string, unknown> | null = null;
    if (pool) {
      const saved = await pool.query(
        `INSERT INTO notifications (title, body, target, created_at)
         VALUES ($1, $2, $3, now())
         RETURNING id, title, body, target, created_at AS "createdAt", scheduled_for AS "scheduledFor"`,
        [title, body, `user:${publicId}`],
      );
      const row = saved.rows[0] as Record<string, unknown> | undefined;
      if (row != null) savedNotification = row;
    }
    res.json({ ok: true, ...out, notification: savedNotification });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    next(new HttpError(502, `Push send failed: ${msg}`, 'PUSH_SEND_FAILED'));
  }
});
