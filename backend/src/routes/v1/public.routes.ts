import { Router } from 'express';
import { fetchPublicConfig } from '../../services/publicConfig';

export const publicRouter = Router();

publicRouter.get('/config', async (_req, res, next) => {
  try {
    const config = await fetchPublicConfig();
    res.json({ ok: true, ...config });
  } catch (e) {
    next(e);
  }
});
