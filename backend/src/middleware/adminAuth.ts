import type { NextFunction, Request, Response } from 'express';
import { env } from '../config/env';
import { HttpError } from './errorHandler';

export function requireAdmin(req: Request, _res: Response, next: NextFunction): void {
  const key = req.header('x-admin-key') ?? req.header('X-Admin-Key');
  if (!env.adminApiKey) {
    next(new HttpError(503, 'ADMIN_API_KEY is not set on the server', 'ADMIN_DISABLED'));
    return;
  }
  if (key !== env.adminApiKey) {
    next(new HttpError(401, 'Invalid admin key', 'UNAUTHORIZED'));
    return;
  }
  next();
}
