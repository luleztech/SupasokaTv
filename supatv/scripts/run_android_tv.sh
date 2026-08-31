#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter run \
  --flavor tv \
  -t lib/main.dart \
  --dart-define=SUPASOKA_VARIANT=tv \
  "$@"
