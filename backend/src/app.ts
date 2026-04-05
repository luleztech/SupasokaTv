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
  const corsOptions =
    env.corsOrigin === '*'
      ? { origin: true as const }
      : { origin: env.corsOrigin as string | string[], credentials: true as const };
  app.use(cors(corsOptions));
  app.use(express.json({ limit: '1mb' }));
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
