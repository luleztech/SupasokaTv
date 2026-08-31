# SupaTV

Big-screen Supasoka viewer for **Android TV** and **Windows** — no mobile UI, no carousel, no bottom tabs.

## Features

- Splash → auto-plays first **free** channel at **480p**
- All channels in a left sidebar; player on the right
- Fullscreen hides the sidebar (F11 or button; Esc to exit)
- Same backend, user ID, premium, and payments as the Supasoka mobile app
- TV payments: subscribe on phone, then tap **Angalia tena** on TV

## Run

**Important:** After adding plugins or changing native code, stop the app and run a **full restart** (`flutter run`) — hot restart alone will break `shared_preferences` on desktop.

```bash
cd supatv
chmod +x scripts/*.sh

# Windows desktop
./scripts/run_windows.sh

# Android TV (device or emulator with leanback)
./scripts/run_android_tv.sh
```

## Build

```bash
./scripts/build_windows.sh
./scripts/build_android_tv.sh
```

## Backend

Uses the same `API_BASE_URL` as Supasoka (Railway by default). Override:

```bash
flutter run --dart-define=API_BASE_URL=https://your-api.example.com
```

## Structure

- `lib/main.dart` — bootstrap + shared Supasoka services
- `lib/screens/tv_shell_screen.dart` — split layout
- `lib/widgets/tv_embedded_player.dart` — media_kit player (480p default)
- Depends on `../` (supasoka package) for config, playback, subscriptions
