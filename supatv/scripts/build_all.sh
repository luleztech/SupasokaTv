#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
chmod +x scripts/*.sh

echo "==> Android TV"
./scripts/build_android_tv.sh

if [[ "$(uname -s)" =~ ^(MINGW|MSYS|CYGWIN|Windows) ]]; then
  echo "==> Windows"
  ./scripts/build_windows.sh
else
  echo "==> Windows skipped (requires Windows host or CI workflow)"
fi

echo ""
echo "Releases in: $ROOT/releases/"
ls -lh "$ROOT/releases/" 2>/dev/null || true
