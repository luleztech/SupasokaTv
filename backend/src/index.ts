import { createApp } from './app';
import { env } from './config/env';
import { logger } from './lib/logger';

const app = createApp();

const server = app.listen(env.port, '0.0.0.0', () => {
  logger.info({ port: env.port, env: env.nodeEnv }, 'server_started');
});

function shutdown(signal: string): void {
  logger.info({ signal }, 'shutdown');
  server.close(() => process.exit(0));
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
