import 'dotenv/config';

function parseOrigins(raw: string | undefined): string | string[] {
  if (!raw || raw === '*') return '*';
  return raw.split(',').map((s) => s.trim()).filter(Boolean);
}

export const env = {
  nodeEnv: process.env.NODE_ENV ?? 'development',
  isProd: process.env.NODE_ENV === 'production',
  port: Number.parseInt(process.env.PORT ?? '3000', 10),
  corsOrigin: parseOrigins(process.env.CORS_ORIGIN),
} as const;
