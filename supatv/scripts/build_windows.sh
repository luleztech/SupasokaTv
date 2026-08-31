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

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*|Windows*)
    ;;
  *)
    echo "Windows release builds must run on a Windows machine (or CI)."
    echo "On this host, use GitHub Actions: .github/workflows/supatv-release.yml"
    exit 1
    ;;
esac

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
OUT_DIR="$ROOT/releases"
BUILD_DIR="$ROOT/build/windows/x64/runner/Release"
OUT_ZIP="$OUT_DIR/supatv-${VERSION}-windows-x64.zip"

flutter pub get
flutter build windows --release \
  --dart-define=SUPASOKA_VARIANT=desktop \
  "$@"

mkdir -p "$OUT_DIR"
rm -f "$OUT_ZIP"
(
  cd "$BUILD_DIR"
  zip -r "$OUT_ZIP" .
)

echo ""
echo "✓ Windows release folder: $BUILD_DIR"
echo "✓ Windows release zip:    $OUT_ZIP"
ls -lh "$OUT_ZIP"
