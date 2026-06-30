import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import pinoHttp from 'pino-http';
import { env } from './config/env';
import { logger } from './lib/logger';
import { errorHandler } from './middleware/errorHandler';
import { notFound } from './middleware/notFound';
import { apiRouter } from './routes';

export function createApp(): express.Application {
  const app = express();

  app.disable('x-powered-by');
  app.use(helmet());
  app.use(
    cors({
      credentials: true,
      origin: (origin, callback) => {
        // Non-browser or same-origin requests.
        if (!origin) {
          callback(null, true);
          return;
        }
        // Always allow local SupaAdmin web dev origins.
        if (origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:')) {
          callback(null, true);
          return;
        }
        if (env.corsOrigin === '*') {
          callback(null, true);
          return;
        }
        const allowed = Array.isArray(env.corsOrigin) ? env.corsOrigin : [env.corsOrigin];
        callback(null, allowed.includes(origin));
      },
    }),
  );
  app.use(
    '/api/v1/public/sonicpesa/webhook',
    express.raw({ type: () => true, limit: '1mb' }),
    (req, _res, next) => {
      const buf = req.body;
      if (Buffer.isBuffer(buf)) {
        const raw = buf.toString('utf8');
        (req as express.Request & { rawBody?: string }).rawBody = raw;
        try {
          req.body = raw.length ? JSON.parse(raw) : {};
        } catch {
          req.body = {};
        }
      }
      next();
    },
  );
  app.use(express.json({ limit: '5mb' }));
  app.use(
    pinoHttp({
      logger,
      autoLogging: env.isProd ? { ignore: (req) => req.url === '/api/v1/health' } : true,
    }),
  );

  app.get('/', (_req, res) => {
    res.json({
      ok: true,
      name: 'supasoka-api',
      docs: '/api/v1/health',
    });
  });

  app.use('/api', apiRouter);

  app.use(notFound);
  app.use(errorHandler);

  return app;
}
