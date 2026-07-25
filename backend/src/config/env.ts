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
  /** SonicPesa — same account/credentials as EaMax (Railway env). */
  sonicPesaApiKey: process.env.SONICPESA_API_KEY ?? '',
  sonicPesaSecretKey:
    process.env.SONICPESA_SECRET_KEY ??
    process.env.SONICPESA_API_SECRET ??
    process.env.SONICPESA_SECRETE_KEY ??
    '',
  sonicPesaWebhookSecret: process.env.SONICPESA_WEBHOOK_SECRET ?? '',
  /** Aurax Pay — fallback when Sonic cannot deliver Vodacom M-Pesa or Halopesa STK. */
  auraxPayApiKey: process.env.AURAXPAY_API_KEY ?? '',
  auraxPayWebhookSecret: process.env.AURAXPAY_WEBHOOK_SECRET ?? '',
  auraxPayWebhookUrl: process.env.AURAXPAY_WEBHOOK_URL ?? '',
  publicBaseUrl: (() => {
    const explicit = (process.env.PUBLIC_BASE_URL ?? '').trim();
    if (explicit) return explicit.replace(/\/$/, '');
    const railway = (process.env.RAILWAY_PUBLIC_DOMAIN ?? '').trim();
    if (railway) return `https://${railway.replace(/^https?:\/\//, '')}`;
    return 'https://supasokatv-production.up.railway.app';
  })(),
  /** FCM service-account credentials for backend push broadcast. */
  fcmProjectId: process.env.FCM_PROJECT_ID ?? '',
  fcmClientEmail: process.env.FCM_CLIENT_EMAIL ?? '',
  fcmPrivateKey: (process.env.FCM_PRIVATE_KEY ?? '').replace(/\\n/g, '\n'),
  /** Optional: absolute path to Firebase service-account json (local/dev). */
  fcmServiceAccountPath: process.env.FCM_SERVICE_ACCOUNT_PATH ?? '',
  /** Optional: full Firebase service-account json string (single env var). */
  fcmServiceAccountJson: process.env.FCM_SERVICE_ACCOUNT_JSON ?? '',
  /** EaMax API base (e.g. https://eamax-production.up.railway.app) — mirrors SupaAdmin push to EaMax users. */
  eamaxApiBaseUrl: process.env.EAMAX_API_BASE_URL ?? '',
  /** Shared secret; must match EaMax SUPA_EAMAX_BRIDGE_SECRET. */
  eamaxBridgeSecret: process.env.EAMAX_BRIDGE_SECRET ?? '',
} as const;
