import { Router } from 'express';
import { importAppConfig } from '../../services/adminImport';
import { requireAdmin } from '../../middleware/adminAuth';

export const adminRouter = Router();

adminRouter.post('/import', requireAdmin, async (req, res, next) => {
  try {
    await importAppConfig(req.body);
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});
