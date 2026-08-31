#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  for candidate in "$HOME/flutter/bin/flutter" "/opt/flutter/bin/flutter"; do
    if [[ -x "$candidate" ]]; then
      export PATH="$(dirname "$candidate"):$PATH"
      break
    fi
  done
fi
command -v flutter >/dev/null 2>&1 || { echo "flutter not found in PATH"; exit 1; }

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
OUT_DIR="$ROOT/releases"
APK_SRC="$ROOT/build/app/outputs/flutter-apk/app-tv-release.apk"
OUT_APK="$OUT_DIR/supatv-${VERSION}-android-tv.apk"

flutter pub get
flutter build apk --release \
  --flavor tv \
  --dart-define=SUPASOKA_VARIANT=tv \
  "$@"

mkdir -p "$OUT_DIR"
cp -f "$APK_SRC" "$OUT_APK"
echo ""
echo "✓ Android TV release: $OUT_APK"
ls -lh "$OUT_APK"
