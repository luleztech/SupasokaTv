import { createApp } from './app';
import { env } from './config/env';
import { logger } from './lib/logger';
import { reconcileUnactivatedPaidIntents } from './services/unifiedPayments';

const app = createApp();

const RECONCILE_MS = 45_000;
let reconcileRunning = false;

async function runPaymentReconcileSweep(): Promise<void> {
  if (reconcileRunning) return;
  reconcileRunning = true;
  try {
    const n = await reconcileUnactivatedPaidIntents(40);
    if (n > 0) {
      logger.info({ activated: n }, 'payment_reconcile_sweep_done');
    }
  } catch (e) {
    logger.warn({ err: e instanceof Error ? e.message : String(e) }, 'payment_reconcile_sweep_error');
  } finally {
    reconcileRunning = false;
  }
}

const server = app.listen(env.port, '0.0.0.0', () => {
  logger.info({ port: env.port, env: env.nodeEnv }, 'server_started');
  // Catch paid-but-not-premium cases if webhook/status race missed the client.
  void runPaymentReconcileSweep();
  setInterval(() => {
    void runPaymentReconcileSweep();
  }, RECONCILE_MS).unref?.();
});

function shutdown(signal: string): void {
  logger.info({ signal }, 'shutdown');
  server.close(() => process.exit(0));
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
