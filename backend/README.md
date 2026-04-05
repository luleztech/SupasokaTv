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
| `JWT_SECRET` | Long random string; used only on the server to sign admin JWTs |
| `ADMIN_APP_PASSWORD` | Password for **SupaAdmin** sign-in (`POST /api/v1/auth/admin-login`). **Not** the old API key — the mobile app stores a **short-lived JWT**, not this password. |

### Optional

| Variable | Notes |
|----------|--------|
| `PORT` | Railway sets this (often `8080`) |
| `NODE_ENV` | `production` in deploy |
| `CORS_ORIGIN` | `*` or your Flutter web origin |
| `ADMIN_API_KEY` | **Legacy only** — for `curl`/scripts with header `X-Admin-Key`. **SupaAdmin mobile does not use this.** |

### Viewer app (read-only)

The user app calls **`GET /api/v1/public/config`** — no admin secret. Set the Flutter app’s API base URL (`lib/config/deployment.dart` or `--dart-define=API_BASE_URL=…`) to this service’s **public HTTPS URL**.

### After deploy

1. `curl -sS https://YOUR-API/api/v1/health` → JSON OK  
2. In SupaAdmin: **Settings** → same API URL → **Admin password** = `ADMIN_APP_PASSWORD` → **Sign in & load from server**  
3. Edits → **Push to DB** → viewer pull-to-refresh should show channels.

## Endpoints

- `GET /` — service banner  
- `GET /api/v1/health` — JSON health (Railway healthcheck)  
- `POST /api/v1/auth/admin-login` — `{ "password": "..." }` → `{ ok, token }` (JWT)  
- `GET /api/v1/admin/export` — full config (requires admin JWT or legacy key)  
- `POST /api/v1/admin/import` — write config to Postgres  
- `GET /api/v1/public/config` — public config for the viewer app  

## Railway (API service)

1. New service → GitHub repo → **Root directory:** `backend`  
2. Build: `npm run build` · Start: `npm start`  
3. **Variables:** `DATABASE_URL`, `JWT_SECRET`, `ADMIN_APP_PASSWORD`  
4. Public HTTPS URL → copy into Flutter `kRailwayApiBaseUrl` / `API_BASE_URL`  

Keep the Flutter **web** service and this **API** as **two** Railway services if you use both.
