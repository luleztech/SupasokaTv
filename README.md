# SupasokaTv

Supasoka — Flutter live TV / streaming viewer app (Android, iOS, web, desktop).

This repository contains the **user-facing Flutter app** and a **Node.js API** under `backend/`.

| Part | Stack | Deploy |
|------|--------|--------|
| Root | Flutter (mobile + web) | e.g. Railway Docker (`Dockerfile` at repo root) |
| `backend/` | Node 20 + TypeScript + Express | Railway: set **root directory** to `backend` (see `backend/README.md`) |

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) SDK (see `pubspec.yaml` for the Dart SDK constraint)

## Run

```bash
flutter pub get
flutter run
```

## Build for release (example)

```bash
flutter build apk
# or
flutter build appbundle
```

## Deploy on [Railway](https://railway.app)

**Production (Flutter web):** [https://supasokatv-production.up.railway.app](https://supasokatv-production.up.railway.app)

The root **`Dockerfile`** runs `flutter build web --release` and serves static files with [`serve`](https://www.npmjs.com/package/serve). The process **must listen on `PORT`** (Railway sets this; use **8080** in variables if you pin a port — the container binds `0.0.0.0:$PORT`).

1. Create a project → **Deploy from GitHub** → select this repo (root directory = repo root).
2. Use **Dockerfile** / `railway.json` — do **not** rely on Railpack for the Flutter app.
3. **Variables (optional):** `PORT=8080` if you want a fixed internal port; otherwise Railway assigns `PORT` automatically.
4. **Networking:** public hostname `supasokatv-production.up.railway.app` → routes to the service on `$PORT`.

Canonical URL is also in code: `lib/config/deployment.dart` → `kRailwayWebUrl`.

### Railway variables (Flutter web service — root `Dockerfile`)

| Variable | Required? | Typical value | Notes |
|----------|-------------|---------------|--------|
| *(none)* | — | — | **Deploy can succeed with zero custom variables.** Railway injects **`PORT`** for you. |
| `PORT` | No | *(auto)* | Only set manually if you want a fixed port (e.g. `8080`). Usually **leave unset** and let Railway assign it. |
| `NODE_ENV` | No | `production` | Optional; only affects the small `serve` process in the final image. |

**Backend service** (`backend/` root in a **second** Railway service): set `NODE_ENV=production`; add `CORS_ORIGIN=https://supasokatv-production.up.railway.app` if the browser calls the API from your web app. **`PORT`** is still injected by Railway — you normally do **not** define it yourself.

If the Docker build fails, it is usually a **Flutter compile error** (fix in `lib/`), not missing env vars.

Local Docker smoke test:

```bash
docker build -t supasoka-web .
docker run -p 8080:8080 -e PORT=8080 supasoka-web
# http://localhost:8080
```

## License

See the repository owner for licensing.
