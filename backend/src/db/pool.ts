import { Pool } from 'pg';
import { env } from '../config/env';
import { logger } from '../lib/logger';

let pool: Pool | null = null;

export function getPool(): Pool | null {
  if (!env.databaseUrl) {
    return null;
  }
  if (!pool) {
    const conn = env.databaseUrl;
    const useSsl =
      conn.includes('railway') ||
      conn.includes('amazonaws.com') ||
      conn.includes('sslmode=require');
    pool = new Pool({
      connectionString: conn,
      max: 10,
      ssl: useSsl ? { rejectUnauthorized: false } : undefined,
    });
    pool.on('error', (err) => {
      logger.error({ err }, 'pg_pool_error');
    });
  }
  return pool;
}

export async function closePool(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}
