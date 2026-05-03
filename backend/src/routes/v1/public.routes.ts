import { Router } from 'express';
import { fetchPublicConfig, fetchPublicConfigMeta } from '../../services/publicConfig';
import { registerPublicUser, getUserPremiumStatus } from '../../services/userDirectory';

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
