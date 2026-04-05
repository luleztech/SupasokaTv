# SupasokaTv

Supasoka — Flutter live TV / streaming viewer app (Android, iOS, web, desktop).

This repository contains the **user-facing Flutter app** and a **Node.js API** under `backend/`.

| Part | Stack | Deploy |
|------|--------|--------|
| Root | Flutter (mobile + web) | e.g. Railway Docker (`Dockerfile` at repo root) |
| `backend/` | Node 20 + TypeScript + Express | Railway: set **root directory** to `backend` (see `backend/README.md`) |

## PostgreSQL (Railway)

SQL schema and apply script live in **`database/`** (see [`database/README.md`](database/README.md)).

```bash
railway run bash database/apply.sh
# or from psql: \i .../database/schema.sql
```

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) SDK (see `pubspec.yaml` for the Dart SDK constraint)

## Run

```bash
flutter pub get
flutter run
```

The app loads public config from the API. Resolution is in `lib/config/api_config.dart`:

| Scenario | Default API base |
|----------|------------------|
| **Web, debug** (`flutter run -d chrome`) | `http://localhost:8080` — start the API locally: `cd backend && npm install && npm run dev` |
| **Mobile / desktop / web release build** | `kRailwayApiBaseUrl` in `lib/config/deployment.dart` (must be your real backend URL) |

Override anytime:

```bash
flutter run --dart-define=API_BASE_URL=https://your-api.up.railway.app
# local backend on another port:
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

### Railway: two services (web vs API)

| Service | Repo root in Railway | Used for |
|---------|------------------------|----------|
| Node **API** | `backend/` | Mobile app + `kRailwayApiBaseUrl` in `lib/config/deployment.dart` |

If you only ship the **mobile app**, one Railway service with root **`backend/`** is enough; set `kRailwayApiBaseUrl` to that service’s public HTTPS URL.

### Release APK / App Bundle (API URL)

1. Deploy **`backend/`** on Railway (separate service) and copy its **public HTTPS URL** (no path, no `:8080`).
2. Paste that URL into `lib/config/deployment.dart` → `kRailwayApiBaseUrl`, **or** build with defines:

```bash
cp dart_defines.example.json dart_defines.json
# Edit dart_defines.json — set API_BASE_URL to your backend URL
flutter build apk --dart-define-from-file=dart_defines.json
```

Or a single flag:

```bash
flutter build apk --dart-define=API_BASE_URL=https://YOUR-BACKEND-xxxx.up.railway.app
```

## Build for release (example)

```bash
flutter build apk
# or
flutter build appbundle
```

Use `--dart-define=…` or `--dart-define-from-file=dart_defines.json` whenever `kRailwayApiBaseUrl` in `deployment.dart` is empty or you want to override it.

## Deploy on [Railway](https://railway.app)

**Production (Flutter web):** [https://supasokatv-production.up.railway.app](https://supasokatv-production.up.railway.app)

The root **`Dockerfile`** runs `flutter build web --release` and serves static files with [`serve`](https://www.npmjs.com/package/serve). The process **must listen on `PORT`** (Railway sets this; use **8080** in variables if you pin a port — the container binds `0.0.0.0:$PORT`).

1. Create a project → **Deploy from GitHub** → select this repo (root directory = repo root).
2. Use **Dockerfile** / `railway.json` — do **not** rely on Railpack for the Flutter app.
3. **Variables (optional):** `PORT=8080` if you want a fixed internal port; otherwise Railway assigns `PORT` automatically.
4. **Networking:** public hostname `supasokatv-production.up.railway.app` → routes to the service on `$PORT`.

Canonical API base for the mobile app: `lib/config/deployment.dart` → `kRailwayApiBaseUrl`.

For the root **Dockerfile** (Flutter web image), set Railway **build** variable `API_BASE_URL` to the same backend URL so `flutter build web` embeds it (see `Dockerfile` `ARG API_BASE_URL`).

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
