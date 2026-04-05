import type { NextFunction, Request, Response } from 'express';
import jwt, { type JwtPayload } from 'jsonwebtoken';

import { env } from '../config/env';
import { HttpError } from './errorHandler';

/**
 * Accepts `Authorization: Bearer <jwt>` (SupaAdmin) or `X-Admin-Key` (legacy curl/scripts).
 */
export function requireAdmin(req: Request, _res: Response, next: NextFunction): void {
  const authHeader = req.header('authorization') ?? req.header('Authorization');
  const bearer = authHeader?.match(/^Bearer\s+(.+)$/i);
  const token = bearer?.[1]?.trim();

  if (token && env.jwtSecret) {
    try {
      const decoded = jwt.verify(token, env.jwtSecret) as JwtPayload & { role?: string };
      if (decoded.role === 'admin') {
        next();
        return;
      }
    } catch {
      /* try API key below */
    }
  }

  const key = req.header('x-admin-key') ?? req.header('X-Admin-Key');
  if (env.adminApiKey && key === env.adminApiKey) {
    next();
    return;
  }

  const configured = Boolean(env.jwtSecret && env.adminAppPassword) || Boolean(env.adminApiKey);
  if (!configured) {
    next(
      new HttpError(
        503,
        'Admin auth not configured: set JWT_SECRET + ADMIN_APP_PASSWORD (recommended) or ADMIN_API_KEY on the server',
        'ADMIN_DISABLED',
      ),
    );
    return;
  }

  next(new HttpError(401, 'Unauthorized — sign in again or use a valid admin token', 'UNAUTHORIZED'));
}
