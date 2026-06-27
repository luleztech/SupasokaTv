import { getPool } from '../db/pool';

export const PAYMENT_PROVIDER_SETTING_KEY = 'payment_provider';

/** SonicPesa is the only supported mobile-money gateway. */
export type PaymentProviderId = 'sonicpesa';

export const PAYMENT_PROVIDERS = {
  SONICPESA: 'sonicpesa' as const,
};

export function normalizePaymentProvider(_raw: unknown): PaymentProviderId {
  return PAYMENT_PROVIDERS.SONICPESA;
}

export function isSonicPesaConfigured(): boolean {
  return Boolean(process.env.SONICPESA_API_KEY?.trim());
}

export function isProviderConfigured(_provider?: PaymentProviderId): boolean {
  return isSonicPesaConfigured();
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
  if (pool) {
    await ensureAppSettingsTable();
    await pool.query(
      `INSERT INTO app_settings (key, value) VALUES ($1, $2)
       ON CONFLICT (key) DO UPDATE SET value = $2`,
      [PAYMENT_PROVIDER_SETTING_KEY, PAYMENT_PROVIDERS.SONICPESA],
    );
  }
  return PAYMENT_PROVIDERS.SONICPESA;
}

export async function setPaymentProvider(_provider: PaymentProviderId): Promise<void> {
  const pool = getPool();
  if (!pool) throw new Error('DATABASE_URL is not configured');
  await ensureAppSettingsTable();
  await pool.query(
    `INSERT INTO app_settings (key, value) VALUES ($1, $2)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [PAYMENT_PROVIDER_SETTING_KEY, PAYMENT_PROVIDERS.SONICPESA],
  );
}
