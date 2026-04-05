import 'dotenv/config';

function parseOrigins(raw: string | undefined): string | string[] {
  if (!raw || raw === '*') return '*';
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
}

export const env = {
  nodeEnv: process.env.NODE_ENV ?? 'development',
  isProd: process.env.NODE_ENV === 'production',
  /** Railway sets `PORT` (commonly 8080). Local default matches typical Railway dev. */
  port: Number.parseInt(process.env.PORT ?? '8080', 10),
  corsOrigin: parseOrigins(process.env.CORS_ORIGIN),
} as const;
