# Supasoka database (PostgreSQL)

Schema file: **`schema.sql`** — tables for **users**, **channels**, **carousel_slides**, **premium_packages**, **malipo_plans**, **live_matches**, **notifications**, **app_settings**.

## Apply with Railway CLI (terminal)

From the **repo root** (after `railway link`):

```bash
chmod +x database/apply.sh
railway run bash database/apply.sh
```

This uses **`DATABASE_URL`** that Railway injects for your linked **Postgres** service.

## Apply inside `psql` (your workflow)

```bash
railway connect Postgres
```

Then in `psql`:

```sql
\i /home/ayoub/MySecretes/Supasoka/database/schema.sql
```

Use the **full path** to `schema.sql` on your machine (or `\i` relative path if you started `psql` from the repo root).

## Tables overview

| Table | Purpose |
|-------|---------|
| `users` | Device/user id, `profile_username`, `premium_until_ms`, notes |
| `channels` | Stations: name, category, stream URL, DRM, sort order |
| `carousel_slides` | Home carousel; `channel_id` → `channels` |
| `premium_packages` | Package list (`features` as JSON array) |
| `malipo_plans` | M-Pesa plans (accents, badge, amounts) |
| `live_matches` | Live events; optional `channel_id` |
| `notifications` | Push log / scheduled sends |
| `app_settings` | Key/value (e.g. customer care WhatsApp) |
| `schema_migrations` | Version `1` after first apply |

Re-running **`schema.sql`** is safe (creates missing objects only).

## psql client vs server version

A warning like “psql major version 17, server major version 18” is normal; upgrading local `psql` is optional.
