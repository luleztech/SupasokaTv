import { getPool } from '../db/pool';

export const PAYMENT_PROVIDER_SETTING_KEY = 'payment_provider';

export type PaymentProviderId = 'zeno' | 'sonicpesa';

export const PAYMENT_PROVIDERS = {
  ZENO: 'zeno' as const,
  SONICPESA: 'sonicpesa' as const,
};

export function normalizePaymentProvider(raw: unknown): PaymentProviderId {
  const compact = String(raw ?? '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]/g, '');
  if (compact === 'sonicpesa') return PAYMENT_PROVIDERS.SONICPESA;
  return PAYMENT_PROVIDERS.ZENO;
}

export function isZenoConfigured(): boolean {
  const key =
    process.env.ZENO_API_KEY?.trim() ||
    process.env.ZENOPAY_API_KEY?.trim() ||
    process.env.ZENOURI_API_KEY?.trim() ||
    '';
  return key.length > 0;
}

export function isSonicPesaConfigured(): boolean {
  return Boolean(process.env.SONICPESA_API_KEY?.trim());
}

export function isProviderConfigured(provider: PaymentProviderId): boolean {
  return provider === PAYMENT_PROVIDERS.SONICPESA ? isSonicPesaConfigured() : isZenoConfigured();
}

async function ensureAppSettingsTable(): Promise<void> {
  const pool = getPool();
  if (!pool) return;
  await pool.query(
    `CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )`,
  );
}

export async function getSelectedPaymentProvider(): Promise<PaymentProviderId> {
  const pool = getPool();
  if (!pool) return PAYMENT_PROVIDERS.ZENO;
  await ensureAppSettingsTable();
  const res = await pool.query<{ value: string }>(
    `SELECT value FROM app_settings WHERE key = $1 LIMIT 1`,
    [PAYMENT_PROVIDER_SETTING_KEY],
  );
  const raw = res.rows[0]?.value ?? PAYMENT_PROVIDERS.ZENO;
  return normalizePaymentProvider(raw);
}

export async function setPaymentProvider(provider: PaymentProviderId): Promise<void> {
  const pool = getPool();
  if (!pool) throw new Error('DATABASE_URL is not configured');
  await ensureAppSettingsTable();
  await pool.query(
    `INSERT INTO app_settings (key, value) VALUES ($1, $2)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [PAYMENT_PROVIDER_SETTING_KEY, provider],
  );
}
