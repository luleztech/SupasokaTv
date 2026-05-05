#!/usr/bin/env bash
# Apply incremental SQL migrations (002 → 003) to Railway Postgres or any DB with DATABASE_URL.
#
# Prerequisites: psql client installed locally.
#
# --- Option A: Railway CLI (recommended, repo linked to project) ---
# From the repository root:
#   railway run --service Postgres bash database/run_migrations.sh
#
# If your Postgres plugin service has another name, replace `Postgres`:
#   railway service    # list names
#   railway run --service <PostgresServiceName> bash database/run_migrations.sh
#
# --- Option B: Manual DATABASE_URL ---
# Railway dashboard → Postgres → Variables (or Connect) → copy connection string, then:
#   export DATABASE_URL='postgresql://...'
#   bash database/run_migrations.sh
#
# --- Option C: Already inside `railway connect Postgres` ---
# Use \\i with absolute paths (cannot run this script interactively; exit psql and use Option A/B).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIG="$ROOT/database/migrations"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is not set."
  echo ""
  echo "Try from repo root:"
  echo "  railway run --service Postgres bash database/run_migrations.sh"
  echo ""
  echo "Or:"
  echo "  export DATABASE_URL='postgresql://user:pass@host:port/db'"
  echo "  bash database/run_migrations.sh"
  exit 1
fi

run_sql() {
  local file="$1"
  local name
  name="$(basename "$file")"
  if [[ ! -f "$file" ]]; then
    echo "Missing migration file: $file"
    exit 1
  fi
  echo ""
  echo ">>> Applying $name ..."
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$file"
  echo ">>> OK: $name"
}

echo "Applying migrations from: $MIG"
run_sql "$MIG/002_malipo_accent_bigint.sql"
run_sql "$MIG/003_align_public_config_schema.sql"

echo ""
echo "Done. Redeploy the API service on Railway, then check:"
echo "  curl -sS \"\${API_URL}/api/v1/public/config\" | head -c 200"
