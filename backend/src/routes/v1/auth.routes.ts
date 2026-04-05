import { createHash, timingSafeEqual } from 'crypto';

import { Router } from 'express';
import jwt from 'jsonwebtoken';

import { env } from '../../config/env';
import { HttpError } from '../../middleware/errorHandler';

export const authRouter = Router();

/**
 * SupaAdmin signs in with password only (no API key in the app).
 * Set `ADMIN_APP_PASSWORD` and `JWT_SECRET` on the API service (Railway).
 */
authRouter.post('/admin-login', (req, res, next) => {
  try {
    if (!env.adminAppPassword) {
      throw new HttpError(
        503,
        'ADMIN_APP_PASSWORD is not set on the server (Railway env for this API service)',
        'NO_ADMIN_PASSWORD',
      );
    }
    if (!env.jwtSecret) {
      throw new HttpError(
        503,
        'JWT_SECRET is not set on the server — required to issue admin tokens',
        'NO_JWT_SECRET',
      );
    }

    const pwd = String((req.body as Record<string, unknown>)?.password ?? '');
    const a = createHash('sha256').update(pwd, 'utf8').digest();
    const b = createHash('sha256').update(env.adminAppPassword, 'utf8').digest();
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new HttpError(401, 'Invalid password', 'UNAUTHORIZED');
    }

    const token = jwt.sign({ sub: 'supaadmin', role: 'admin' }, env.jwtSecret, { expiresIn: '7d' });
    res.json({ ok: true, token });
  } catch (e) {
    next(e);
  }
});
