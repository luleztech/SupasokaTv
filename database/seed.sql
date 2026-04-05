-- Demo content for Supasoka (aligned with bundled Flutter defaults + SupaAdmin shapes).
--
-- Prerequisites:
--   • schema.sql applied
--   • If the DB was created before accent columns were widened, run:
--       database/migrations/002_malipo_accent_bigint.sql
--
-- Apply (from repo root, with DATABASE_URL set):
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/seed.sql
-- Or:  railway run bash -c 'psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/seed.sql'

BEGIN;

TRUNCATE carousel_slides, live_matches, malipo_plans, premium_packages, channels RESTART IDENTITY CASCADE;

INSERT INTO app_settings (key, value) VALUES ('customerCareWhatsapp', '212600000000')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();

INSERT INTO channels (id, name, cat, img, free, viewers, stream_url, enabled, drm, clear_key_kid_key, sort_order) VALUES
(0, 'Vero Sports HD', 'football', 'https://picsum.photos/seed/bein1/400/220', TRUE, '24.1K', 'https://example.com/live.php?id=vero', TRUE, 'none', '', 0),
(1, 'Aero Sports Premier', 'football', 'https://picsum.photos/seed/sky2/400/220', FALSE, '18.9K', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', TRUE, 'none', '', 1),
(2, 'Flixora Originals', 'movies', 'https://picsum.photos/seed/netf3/400/220', TRUE, '32K', 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4', TRUE, 'none', '', 2),
(3, 'Cinemax Ultra', 'movies', 'https://picsum.photos/seed/hbo4/400/220', FALSE, '11.3K', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', TRUE, 'none', '', 3),
(4, 'SportVex HD', 'sports', 'https://picsum.photos/seed/espn5/400/220', TRUE, '9.7K', 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4', TRUE, 'none', '', 4),
(5, 'Nexosport HD', 'sports', 'https://picsum.photos/seed/euro6/400/220', FALSE, '7.2K', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', TRUE, 'none', '', 5),
(6, 'Vibra Entertainment', 'entertainment', 'https://picsum.photos/seed/mtv7/400/220', TRUE, '15K', 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4', TRUE, 'none', '', 6),
(7, 'Explorix Channel', 'entertainment', 'https://picsum.photos/seed/disc8/400/220', FALSE, '6.4K', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', TRUE, 'none', '', 7),
(8, 'Globex World News', 'news', 'https://picsum.photos/seed/bbc9/400/220', TRUE, '21K', 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4', TRUE, 'none', '', 8),
(9, 'Arivo News Live', 'news', 'https://picsum.photos/seed/alj10/400/220', FALSE, '13.5K', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', TRUE, 'none', '', 9),
(10, 'Lorium Liga TV', 'football', 'https://picsum.photos/seed/laliga11/400/220', FALSE, '8.8K', 'https://gateway.example.com/embed/player.php?c=10', TRUE, 'none', '', 10),
(11, 'Cinevox Movies 4K', 'movies', 'https://picsum.photos/seed/action12/400/220', TRUE, '19K', 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8', TRUE, 'none', '', 11);

SELECT setval(pg_get_serial_sequence('channels', 'id'), (SELECT COALESCE(MAX(id), 1) FROM channels));

INSERT INTO carousel_slides (badge, badge_icon, title, channel_id, img, sort_order) VALUES
('LIVE NOW', 'radio-outline', E'Lorem Cup\nFinal 2025', 0, 'https://picsum.photos/seed/match1/800/400', 0),
('NEW MOVIE', 'film-outline', E'The Lorem\nIpsum', 2, 'https://picsum.photos/seed/movie22/800/400', 1),
('TONIGHT', 'trophy-outline', E'Lorem League\nDerby Night', 1, 'https://picsum.photos/seed/sport5/800/400', 2),
('ENTERTAINMENT', 'musical-notes-outline', E'Dolor Night\nLive Stream', 3, 'https://picsum.photos/seed/enter9/800/400', 3);

SELECT setval(pg_get_serial_sequence('carousel_slides', 'id'), (SELECT COALESCE(MAX(id), 1) FROM carousel_slides));

INSERT INTO live_matches (id, title, sport, sport_icon, img, channel_id, live_badge, sort_order) VALUES
(0, 'Lorem FC vs Ipsum United', 'Lorem League', 'football-outline', 'https://picsum.photos/seed/live1/400/220', 0, TRUE, 0),
(1, 'Dolor City vs Amet FC', 'Ipsum Liga', 'football-outline', 'https://picsum.photos/seed/live2/400/220', 1, TRUE, 1),
(2, 'Lorem Hawks vs Ipsum Bulls', 'Lorem Basketball', 'basketball-outline', 'https://picsum.photos/seed/live3/400/220', 4, FALSE, 2),
(3, 'Lorem Open Final', 'Lorem Tennis', 'tennisball-outline', 'https://picsum.photos/seed/live4/400/220', 2, TRUE, 3),
(4, 'Lorem Grand Prix Series', 'Ipsum Racing', 'car-sport-outline', 'https://picsum.photos/seed/live5/400/220', 5, FALSE, 4),
(5, 'Lorem Championship Fight', 'Dolor Combat', 'barbell-outline', 'https://picsum.photos/seed/live6/400/220', 3, TRUE, 5);

SELECT setval(pg_get_serial_sequence('live_matches', 'id'), (SELECT COALESCE(MAX(id), 1) FROM live_matches));

INSERT INTO malipo_plans (id, label, price_lines, amount, period, popular, accent1, accent2, badge, sort_order) VALUES
('weekly', 'Wiki 1', E'TSh\n2,000', 'TSh 2,000', 'Wiki Moja', FALSE, 4278235625, 4281745649, 'MPYA', 0),
('monthly', 'Mwezi', E'TSh\n5,000', 'TSh 5,000', 'Mwezi Moja', TRUE, 4289374967, 4293884089, 'BORA', 1),
('yearly', 'Mwaka', E'TSh\n12,000', 'TSh 12,000', 'Mwaka Mzima', FALSE, 4294940075, 4292861912, 'PUNGUZO', 2);

INSERT INTO premium_packages (id, name, price, period, features, popular, sort_order) VALUES
('daily', 'Daily Pass', '$1.99', '/day', '["All Channels","HD Quality","1 Device"]'::jsonb, FALSE, 0),
('weekly', 'Weekly Pack', '$7.99', '/week', '["All Channels","Full HD","2 Devices","Catch-up TV"]'::jsonb, TRUE, 1),
('monthly', 'Monthly Pro', '$19.99', '/month', '["All Channels","4K Ultra","4 Devices","Catch-up TV","Download"]'::jsonb, FALSE, 2);

-- Demo notifications (does not truncate existing rows; safe to re-run)
INSERT INTO notifications (id, title, body, target) VALUES
('seed_welcome', 'Karibu Supasoka', 'Live TV na movie mfululizo kwenye kifaa chako.', 'all')
ON CONFLICT (id) DO NOTHING;

-- Demo users (upsert — refreshes premium windows on each seed run for local testing)
INSERT INTO users (id, profile_username, legacy_user_id, premium_until_ms, note) VALUES
(
  'usr_demo1',
  'k7mpo2a9',
  NULL,
  (EXTRACT(EPOCH FROM (NOW() + INTERVAL '25 days')) * 1000)::BIGINT,
  'Premium active (seed)'
),
(
  'usr_demo2',
  'expired_x3',
  NULL,
  (EXTRACT(EPOCH FROM (NOW() - INTERVAL '5 days')) * 1000)::BIGINT,
  'Expired (seed)'
),
(
  'usr_demo3',
  'free_only',
  NULL,
  NULL,
  'Free tier (seed)'
)
ON CONFLICT (id) DO UPDATE SET
  profile_username = EXCLUDED.profile_username,
  legacy_user_id = EXCLUDED.legacy_user_id,
  premium_until_ms = EXCLUDED.premium_until_ms,
  note = EXCLUDED.note,
  updated_at = now();

COMMIT;
