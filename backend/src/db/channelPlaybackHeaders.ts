import type { Pool } from 'pg';

let columnsReady = false;

/** Adds optional playback header columns on existing databases. */
export async function ensureChannelPlaybackHeaderColumns(pool: Pool): Promise<void> {
  if (columnsReady) return;
  await pool.query(
    `ALTER TABLE channels ADD COLUMN IF NOT EXISTS referer TEXT NOT NULL DEFAULT ''`,
  );
  await pool.query(
    `ALTER TABLE channels ADD COLUMN IF NOT EXISTS origin TEXT NOT NULL DEFAULT ''`,
  );
  await pool.query(
    `ALTER TABLE channels ADD COLUMN IF NOT EXISTS user_agent TEXT NOT NULL DEFAULT ''`,
  );
  columnsReady = true;
}
