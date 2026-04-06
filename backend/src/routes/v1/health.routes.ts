import { Router } from 'express';

import { getPool } from '../../db/pool';

export const healthRouter = Router();

healthRouter.get('/', (_req, res) => {
  res.json({
    ok: true,
    service: 'supasoka-api',
    uptimeSec: Math.round(process.uptime()),
    ts: new Date().toISOString(),
  });
});

/** Like EaMax `/health/db` — public, no auth. Use to verify Railway `DATABASE_URL` before debugging admin/viewer. */
healthRouter.get('/db', async (_req, res) => {
  const pool = getPool();
  if (!pool) {
    res.status(503).json({
      ok: false,
      database: 'not_configured',
      hint: 'Set DATABASE_URL on the API service (Railway Postgres plugin).',
    });
    return;
  }
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true, database: 'connected' });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    res.status(503).json({
      ok: false,
      database: 'error',
      error: message,
    });
  }
});
