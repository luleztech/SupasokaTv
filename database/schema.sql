-- Supasoka PostgreSQL schema (Railway Postgres)
-- Safe to re-run: IF NOT EXISTS for tables and indexes.
-- PostgreSQL 14+

BEGIN;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  profile_username TEXT NOT NULL,
  legacy_user_id TEXT,
  premium_until_ms BIGINT,
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_premium_until ON users (premium_until_ms)
  WHERE premium_until_ms IS NOT NULL;

CREATE TABLE IF NOT EXISTS channels (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  cat TEXT NOT NULL DEFAULT 'movies',
  img TEXT NOT NULL DEFAULT '',
  free BOOLEAN NOT NULL DEFAULT TRUE,
  viewers TEXT NOT NULL DEFAULT '',
  stream_url TEXT NOT NULL DEFAULT '',
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  drm TEXT NOT NULL DEFAULT 'none',
  clear_key_kid_key TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_channels_cat ON channels (cat);
CREATE INDEX IF NOT EXISTS idx_channels_sort ON channels (sort_order);

CREATE TABLE IF NOT EXISTS carousel_slides (
  id SERIAL PRIMARY KEY,
  badge TEXT NOT NULL,
  badge_icon TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL,
  channel_id INTEGER NOT NULL REFERENCES channels (id) ON DELETE CASCADE,
  img TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_carousel_sort ON carousel_slides (sort_order);

CREATE TABLE IF NOT EXISTS premium_packages (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  price TEXT NOT NULL,
  period TEXT NOT NULL,
  features JSONB NOT NULL DEFAULT '[]'::jsonb,
  popular BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS malipo_plans (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  price_lines TEXT NOT NULL,
  amount TEXT NOT NULL,
  period TEXT NOT NULL,
  popular BOOLEAN NOT NULL DEFAULT FALSE,
  accent1 INTEGER NOT NULL,
  accent2 INTEGER NOT NULL,
  badge TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS live_matches (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  sport TEXT NOT NULL DEFAULT '',
  sport_icon TEXT NOT NULL DEFAULT '',
  img TEXT NOT NULL DEFAULT '',
  channel_id INTEGER REFERENCES channels (id) ON DELETE SET NULL,
  live_badge BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_live_matches_sort ON live_matches (sort_order);

CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  target TEXT NOT NULL DEFAULT 'all',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  scheduled_for TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications (created_at DESC);

CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO schema_migrations (version)
VALUES (1)
ON CONFLICT (version) DO NOTHING;

COMMIT;
