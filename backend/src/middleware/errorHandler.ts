import type { NextFunction, Request, Response } from 'express';
import { logger } from '../lib/logger';

export class HttpError extends Error {
  constructor(
    public statusCode: number,
    message: string,
    public code?: string,
  ) {
    super(message);
    this.name = 'HttpError';
  }
}

export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  if (err instanceof HttpError) {
    res.status(err.statusCode).json({
      ok: false,
      error: { message: err.message, code: err.code ?? 'HTTP_ERROR' },
    });
    return;
  }

  logger.error({ err }, 'unhandled_error');
  res.status(500).json({
    ok: false,
    error: { message: 'Internal server error', code: 'INTERNAL' },
  });
}
