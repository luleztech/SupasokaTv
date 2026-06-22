-- Per-channel preferred audio language for playback (ISO 639-1: sw | en).
-- Safe to re-run (PostgreSQL 11+).

ALTER TABLE channels ADD COLUMN IF NOT EXISTS audio_language TEXT NOT NULL DEFAULT 'sw';
