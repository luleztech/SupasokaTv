# Supasoka API

Node.js **20** + **TypeScript** + **Express**. Deploy on [Railway](https://railway.app) (Dockerfile or Nixpacks).

## Layout

| Path | Role |
|------|------|
| `src/config/` | Environment (`dotenv` + `PORT`) |
| `src/routes/` | HTTP routes (`/api/v1/...`) |
| `src/middleware/` | Errors, 404 |
| `src/lib/` | Shared helpers (logger) |

## Scripts

```bash
npm install
npm run dev      # hot reload
npm run build    # emits dist/
npm start        # node dist/index.js
```

## Environment

Copy `.env.example` → `.env` locally.

### Required for production

| Variable | Notes |
|----------|--------|
| `DATABASE_URL` | Postgres connection string (Railway plugin) |
| **`ADMIN_APP_PASSWORD`** | Password for admin login. SupaAdmin uses this to authenticate. |

### Optional

| Variable | Notes |
|----------|--------|
| `JWT_SECRET` | Signs admin JWTs from `POST /api/v1/auth/admin-login` (auto-generated if not set) |
| `ADMIN_API_KEY` | Legacy support for X-Admin-Key header |
| `PORT` | Railway sets this (often `8080`) |
| `NODE_ENV` | `production` in deploy |
| `CORS_ORIGIN` | `*` or your Flutter web origin |

### Viewer app (read-only)

The user app calls **`GET /api/v1/public/config`** — no admin secret. Set the Flutter app’s API base URL (`lib/config/deployment.dart` or `--dart-define=API_BASE_URL=…`) to this service’s **public HTTPS URL**.

### After deploy

1. `curl -sS https://YOUR-API/api/v1/health` → JSON OK  
2. `curl -sS https://YOUR-API/api/v1/health/db` → `{ "ok": true, "database": "connected" }` (if this fails, fix `DATABASE_URL` before debugging admin sync)  
3. **SupaAdmin:** Set the **same** secret in Railway `ADMIN_API_KEY` and in `supaadmin/lib/config/admin_api_config.dart` as `kRailwayAdminApiKey` (or pass `--dart-define=ADMIN_API_KEY=…` when building). There is **no** password or API URL screen — every save calls `POST /admin/import` with `X-Admin-Key`.  
4. Viewer polls `/api/v1/public/config` (no-store headers) about every **45s** and on tab/app resume.

**Alternative:** SupaAdmin **Advanced → JWT** if you use `JWT_SECRET` + `ADMIN_APP_PASSWORD` only (no key in the APK).

## Endpoints

- `GET /` — service banner  
- `GET /api/v1/health` — JSON health (Railway healthcheck)  
- `GET /api/v1/health/db` — verifies Postgres (`SELECT 1`); public, no auth  
- `POST /api/v1/auth/admin-login` — `{ "password": "..." }` → `{ ok, token }` (JWT)  
- `GET /api/v1/admin/export` — full config (requires admin JWT or legacy key)  
- `POST /api/v1/admin/import` — write config to Postgres (channels/carousel/etc. replaced; **users** are upserted only — viewer accounts from `POST /public/register-user` are **never** deleted by import; remove a user with `DELETE /admin/users/:id`)  
- `GET /api/v1/public/config` — public config for the viewer app  

## Railway (API service)

1. New service → GitHub repo → **Root directory:** `backend`  
2. Build: `npm run build` · Start: `npm start`  
3. **Variables:** `DATABASE_URL`, `JWT_SECRET`, `ADMIN_APP_PASSWORD`  
4. Public HTTPS URL → copy into Flutter `kRailwayApiBaseUrl` / `API_BASE_URL`  

Keep the Flutter **web** service and this **API** as **two** Railway services if you use both.
