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

| Variable | Default | Notes |
|----------|---------|--------|
| `PORT` | `8080` | Railway injects this at runtime (align with service port) |
| `NODE_ENV` | `development` | `production` in deploy |
| `CORS_ORIGIN` | `*` | For browser calls from web app: `https://supasokatv-production.up.railway.app` |

**Flutter web (production):** [https://supasokatv-production.up.railway.app](https://supasokatv-production.up.railway.app)

The user app’s default API base URL lives in the repo root at `lib/config/deployment.dart` (`kRailwayApiBaseUrl`). After you create this service’s public URL on Railway, set that constant to match (or use `--dart-define=API_BASE_URL=…` when building).

## Endpoints

- `GET /` — service banner  
- `GET /api/v1/health` — JSON health (use for Railway healthcheck)

## Railway (second service)

1. New service → **GitHub repo** → same repo as the Flutter app.  
2. **Root directory:** `backend`  
3. Deploy: Dockerfile in this folder is picked up via `railway.json`, or use **Railpack/Nixpacks** with:
   - Build: `npm run build`
   - Start: `npm start`
4. Generate a **public URL** for the API and align it with `kRailwayApiBaseUrl` in the Flutter app’s `lib/config/deployment.dart`.

Keep the Flutter **web** service and this **API** as **two** Railway services in one project.
