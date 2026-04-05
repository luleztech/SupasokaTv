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
  databaseUrl: process.env.DATABASE_URL ?? '',
  /** Legacy: scripts / CI. SupaAdmin mobile uses JWT from POST /auth/admin-login. */
  adminApiKey: process.env.ADMIN_API_KEY ?? '',
  /** Password for SupaAdmin sign-in (never ship API keys in the app). */
  adminAppPassword: process.env.ADMIN_APP_PASSWORD ?? '',
  /** Sign admin JWTs (long random string in production). */
  jwtSecret: process.env.JWT_SECRET ?? process.env.ADMIN_JWT_SECRET ?? '',
} as const;
