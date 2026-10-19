#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter run -d windows \
  --dart-define=SUPASOKA_VARIANT=desktop \
  "$@"
