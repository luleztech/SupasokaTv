-- Older Railway DBs may lack columns added after first deploy.
-- `CREATE TABLE IF NOT EXISTS` does not ALTER existing tables — run this once on Postgres.
-- Safe to re-run (PostgreSQL 11+).

-- channels (viewer SELECT uses drm, clear_key_kid_key, sort_order)
ALTER TABLE channels ADD COLUMN IF NOT EXISTS drm TEXT NOT NULL DEFAULT 'none';
ALTER TABLE channels ADD COLUMN IF NOT EXISTS clear_key_kid_key TEXT NOT NULL DEFAULT '';
ALTER TABLE channels ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

-- carousel_slides
ALTER TABLE carousel_slides ADD COLUMN IF NOT EXISTS badge_icon TEXT NOT NULL DEFAULT '';
ALTER TABLE carousel_slides ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

-- malimo (accent BIGINT: see migrations/002_malipo_accent_bigint.sql)
ALTER TABLE malipo_plans ADD COLUMN IF NOT EXISTS badge TEXT NOT NULL DEFAULT '';
ALTER TABLE malipo_plans ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

-- live_matches
ALTER TABLE live_matches ADD COLUMN IF NOT EXISTS live_badge BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE live_matches ADD COLUMN IF NOT EXISTS match_time TEXT;
ALTER TABLE live_matches ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

-- premium_packages
ALTER TABLE premium_packages ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;
