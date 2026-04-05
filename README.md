# SupasokaTv

Supasoka — Flutter live TV / streaming viewer, with a separate **SupaAdmin** app for configuration (channels, carousel, pricing, users, live matches, notifications).

## Repository layout

| Path | Description |
|------|-------------|
| `/` | Main **Supasoka** Flutter app (`lib/`, `android/`, `ios/`, …) |
| `supaadmin/` | **SupaAdmin** Flutter app for content and subscription management |

## Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) SDK (see `pubspec.yaml` for Dart SDK constraint)

## Run the viewer

```bash
flutter pub get
flutter run
```

## Run SupaAdmin

```bash
cd supaadmin
flutter pub get
flutter run
```

## License

See repository owner for licensing.
