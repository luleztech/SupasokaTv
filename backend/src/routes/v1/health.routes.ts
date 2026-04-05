import { Router } from 'express';

export const healthRouter = Router();

healthRouter.get('/', (_req, res) => {
  res.json({
    ok: true,
    service: 'supasoka-api',
    uptimeSec: Math.round(process.uptime()),
    ts: new Date().toISOString(),
  });
});
