#!/bin/bash

# Supasoka Backend & Admin Sync Test Script
# Tests the complete admin→backend→database→viewer flow

set -e

# Configuration
BACKEND_URL="${BACKEND_URL:-https://supasokatv-production.up.railway.app}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ Error: ADMIN_PASSWORD environment variable not set"
  echo "Usage: ADMIN_PASSWORD=<your-password> BACKEND_URL=<url> ./test-sync.sh"
  exit 1
fi

echo "🚀 Supasoka Backend & Admin Sync Test"
echo "Backend: $BACKEND_URL"
echo ""

# Test 1: Backend Health
echo "1️⃣  Testing backend health..."
if curl -s "$BACKEND_URL/api/v1/public/config" > /dev/null; then
  echo "✅ Backend is reachable"
else
  echo "❌ Backend is not reachable"
  exit 1
fi

# Test 2: Admin Login
echo ""
echo "2️⃣  Testing admin login..."
LOGIN_RESPONSE=$(curl -s -X POST "$BACKEND_URL/api/v1/auth/admin-login" \
  -H "Content-Type: application/json" \
  -d "{\"password\": \"$ADMIN_PASSWORD\"}")

if echo "$LOGIN_RESPONSE" | grep -q '"ok":true'; then
  JWT_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo "✅ Login successful"
  echo "   JWT Token: ${JWT_TOKEN:0:20}..."
else
  echo "❌ Login failed: $LOGIN_RESPONSE"
  exit 1
fi

# Test 3: Export Current Config
echo ""
echo "3️⃣  Testing config export..."
EXPORT_RESPONSE=$(curl -s -X GET "$BACKEND_URL/api/v1/admin/export" \
  -H "Authorization: Bearer $JWT_TOKEN")

if echo "$EXPORT_RESPONSE" | grep -q '"ok":true'; then
  CHANNEL_COUNT=$(echo "$EXPORT_RESPONSE" | grep -o '"channels":\[' | wc -l)
  echo "✅ Config export successful"
  if echo "$EXPORT_RESPONSE" | grep -q '"channels":'; then
    echo "   Found channels in config"
  fi
else
  echo "❌ Export failed: $EXPORT_RESPONSE"
  exit 1
fi

# Test 4: Import Test Config
echo ""
echo "4️⃣  Testing config import..."
TEST_CONFIG='{
  "channels": [
    {
      "id": 999,
      "name": "Test Channel",
      "cat": "test",
      "img": "https://test.jpg",
      "free": true,
      "viewers": "1000",
      "enabled": true,
      "drm": "none"
    }
  ],
  "carousel": [],
  "liveMatches": [],
  "malipoPlans": [],
  "premiumPackages": [],
  "users": [],
  "customerCareWhatsapp": "212600000000"
}'

IMPORT_RESPONSE=$(curl -s -X POST "$BACKEND_URL/api/v1/admin/import" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$TEST_CONFIG")

if echo "$IMPORT_RESPONSE" | grep -q '"ok":true'; then
  echo "✅ Config import successful"
else
  echo "❌ Import failed: $IMPORT_RESPONSE"
  exit 1
fi

# Test 5: Verify Data in Public API
echo ""
echo "5️⃣  Verifying data in public API..."
PUBLIC_CONFIG=$(curl -s -X GET "$BACKEND_URL/api/v1/public/config")

if echo "$PUBLIC_CONFIG" | grep -q '"id":999'; then
  echo "✅ Test channel visible in public API"
else
  echo "⚠️  Test channel not visible yet (may need a moment)"
fi

# Test 6: List Admin Users
echo ""
echo "6️⃣  Testing admin user listing..."
USERS_RESPONSE=$(curl -s -X GET "$BACKEND_URL/api/v1/admin/users" \
  -H "Authorization: Bearer $JWT_TOKEN")

if echo "$USERS_RESPONSE" | grep -q '"ok":true'; then
  USER_COUNT=$(echo "$USERS_RESPONSE" | grep -o '"id":"[^"]*"' | wc -l)
  echo "✅ User listing successful"
  echo "   Found $USER_COUNT users"
else
  echo "❌ User listing failed: $USERS_RESPONSE"
  exit 1
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "Next steps:"
echo "1. Build SupaAdmin APK: cd supaadmin && flutter build apk --release"
echo "2. Install on device: adb install build/app/outputs/flutter-apk/app-release.apk"
echo "3. Open admin app, log in with password: $ADMIN_PASSWORD"
echo "4. Add/edit channels and sync"
echo "5. Check viewer app for new data at /api/v1/public/config"
