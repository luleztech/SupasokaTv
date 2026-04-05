import { Router } from 'express';
import { fetchPublicConfig } from '../../services/publicConfig';
import { registerPublicUser } from '../../services/userDirectory';

export const publicRouter = Router();

publicRouter.get('/config', async (_req, res, next) => {
  try {
    const config = await fetchPublicConfig();
    res.json({ ok: true, ...config });
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
