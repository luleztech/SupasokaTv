-- Optional per-channel Referer, Origin, and User-Agent sent with playback requests.
-- Safe to re-run (PostgreSQL 11+).

ALTER TABLE channels ADD COLUMN IF NOT EXISTS referer TEXT NOT NULL DEFAULT '';
ALTER TABLE channels ADD COLUMN IF NOT EXISTS origin TEXT NOT NULL DEFAULT '';
ALTER TABLE channels ADD COLUMN IF NOT EXISTS user_agent TEXT NOT NULL DEFAULT '';
