# SupasokaTv

Supasoka — Flutter live TV / streaming viewer app (Android, iOS, web, desktop).

This repository contains the **user-facing app** only.

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

This repo includes a **`Dockerfile`** that runs `flutter build web --release` and serves the output with [`serve`](https://www.npmjs.com/package/serve) on **`PORT`** (required by Railway).

1. Create a project → **Deploy from GitHub** → select this repo.
2. Railway should pick **Dockerfile** (see `railway.json`). Do **not** use Railpack-only mode for this repo — Flutter is not auto-detected.
3. After deploy, open the generated **public URL** (Settings → Networking → Generate domain).

To test the image locally:

```bash
docker build -t supasoka-web .
docker run -p 8080:8080 -e PORT=8080 supasoka-web
# http://localhost:8080
```

## License

See the repository owner for licensing.
