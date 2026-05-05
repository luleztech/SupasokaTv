import { Router } from 'express';
import { fetchAdminExportConfig } from '../../services/adminExport';
import { importAppConfig } from '../../services/adminImport';
import { requireAdmin } from '../../middleware/adminAuth';
import { deleteUserById, listUsersForAdmin } from '../../services/userDirectory';

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
