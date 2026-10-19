#!/usr/bin/env bash
# Apply database/schema.sql to Railway Postgres.
#
# Usage:
#   cd /path/to/Supasoka
#   railway run bash database/apply.sh
#
# Or with DATABASE_URL already set:
#   bash database/apply.sh
#
# Interactive psql:
#   railway connect Postgres
#   \i /full/path/to/Supasoka/database/schema.sql

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL="$ROOT/database/schema.sql"

if [[ ! -f "$SQL" ]]; then
  echo "Missing: $SQL"
  exit 1
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is not set."
  echo "Run: railway run bash database/apply.sh"
  echo "Or: railway connect Postgres  then  \\i $SQL"
  exit 1
fi

echo "Applying schema..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$SQL"
echo "Done."
