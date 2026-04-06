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
| **`ADMIN_API_KEY`** | **Recommended for SupaAdmin (EaAdmin-style):** long random secret. Same value must be passed into the admin APK with `--dart-define=ADMIN_API_KEY=…`. All admin routes accept header `X-Admin-Key: <value>`. |

### Optional (JWT admin login)

| Variable | Notes |
|----------|--------|
| `JWT_SECRET` | Signs admin JWTs from `POST /api/v1/auth/admin-login` |
| `ADMIN_APP_PASSWORD` | Password for that JWT flow (SupaAdmin **Advanced → Sign in JWT**) |

### Other optional

| Variable | Notes |
|----------|--------|
| `PORT` | Railway sets this (often `8080`) |
| `NODE_ENV` | `production` in deploy |
| `CORS_ORIGIN` | `*` or your Flutter web origin |

### Viewer app (read-only)

The user app calls **`GET /api/v1/public/config`** — no admin secret. Set the Flutter app’s API base URL (`lib/config/deployment.dart` or `--dart-define=API_BASE_URL=…`) to this service’s **public HTTPS URL**.

### After deploy

1. `curl -sS https://YOUR-API/api/v1/health` → JSON OK  
2. `curl -sS https://YOUR-API/api/v1/health/db` → `{ "ok": true, "database": "connected" }` (if this fails, fix `DATABASE_URL` before debugging admin sync)  
3. **SupaAdmin (default):** Build with `--dart-define=ADMIN_API_KEY=<same as Railway>` (and optional `--dart-define=API_BASE_URL=…`). No password in the UI — edits sync with `X-Admin-Key`.  
4. Edits auto-push to Postgres; viewer **`GET /api/v1/public/config`** shows channels after refresh.

**Alternative:** SupaAdmin **Advanced → JWT** if you use `JWT_SECRET` + `ADMIN_APP_PASSWORD` only (no key in the APK).

## Endpoints

- `GET /` — service banner  
- `GET /api/v1/health` — JSON health (Railway healthcheck)  
- `GET /api/v1/health/db` — verifies Postgres (`SELECT 1`); public, no auth  
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
