# ⚡ Quick Start Guide - Supasoka Admin Backend Sync

## Overview
**Admin app now saves everything to Railway PostgreSQL via Node.js backend. No more local-only storage!**

```
Admin (Password) → Backend JWT → Database → Viewer App
```

---

## 🚀 Quick Start (5 Steps)

### Step 1: Backend Environment Setup (Railway)
Go to your Railway backend service settings and add these environment variables:

```
DATABASE_URL       postgres://...your-railway-postgres-url...
ADMIN_APP_PASSWORD MySecurePassword123
JWT_SECRET         d3adb33f9af0ec12c0deb33fa0ec12c0deb33f123456789
```

> **Note:** Generate a random `JWT_SECRET` (32+ characters)

### Step 2: Verify Backend Runs
```bash
cd backend
npm run build    # Should succeed with no errors
```

If it builds, your backend is ready for Railway deployment.

### Step 3: Build Admin App
```bash
cd supaadmin
flutter clean
flutter pub get
flutter build apk --release
```

**Output:** `supaadmin/build/app/outputs/flutter-apk/app-release.apk`

> **Optional:** Override backend URL with:
> ```bash
> flutter build apk --release --dart-define=API_BASE_URL=https://your-backend.com
> ```

### Step 4: Install & Test Admin
```bash
# Install APK
adb install supaadmin/build/app/outputs/flutter-apk/app-release.apk

# Open app
# 1. Enter admin password (e.g., "MySecurePassword123")
# 2. Add a test channel
# 3. Click "Save" or "Sync"
# 4. Wait for green checkmark (success) or red X (error)
```

**Expected:** No "500" or "503" errors. Sync should say "Successful" or show status in dashboard.

### Step 5: Build & Test Viewer App
```bash
cd ..
flutter build apk --release --dart-define=API_BASE_URL=https://your-backend.com
adb install build/app/outputs/flutter-apk/app-release.apk

# Open app - should show channels/carousel you added in admin
```

---

## 🔍 Verify It Works

### Quick Test (requires `curl`)
```bash
# Set your backend URL and password
BACKEND=https://supasokatv-production.up.railway.app
PASSWORD=MySecurePassword123

# 1. Login
TOKEN=$(curl -s -X POST $BACKEND/api/v1/auth/admin-login \
  -H "Content-Type: application/json" \
  -d "{\"password\": \"$PASSWORD\"}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

echo "Token: $TOKEN"

# 2. Export config
curl -s -X GET $BACKEND/api/v1/admin/export \
  -H "Authorization: Bearer $TOKEN" | head -100

# 3. Check public API
curl -s -X GET $BACKEND/api/v1/public/config | head -100
```

### Or Use Test Script
```bash
ADMIN_PASSWORD="MySecurePassword123" ./test-sync.sh
```

---

## 📱 What Changed in Admin App

| Before | After |
|--------|-------|
| ❌ API URL in admin UI | ✅ No API URL field (built-in) |
| ❌ Save button sent nowhere | ✅ Save posts to `/api/v1/admin/import` |
| ❌ Data only in SharedPrefs | ✅ Data in PostgreSQL immediately |
| ❌ Manual "cloud" setup | ✅ Backend manages everything |
| ❌ No JWT auth | ✅ Password → JWT token (7 days) |

---

## 🛠️ API Reference

### Admin Endpoints (Require JWT Bearer Token)

**Login (no auth needed):**
```bash
POST /api/v1/auth/admin-login
Content-Type: application/json

{"password": "MySecurePassword123"}

# Response:
{"ok": true, "token": "eyJ..."}
```

**Export Config:**
```bash
GET /api/v1/admin/export
Authorization: Bearer eyJ...

# Response:
{"ok": true, "channels": [...], "carousel": [...], ...}
```

**Import Config (Save):**
```bash
POST /api/v1/admin/import
Authorization: Bearer eyJ...
Content-Type: application/json

{
  "channels": [{"id": 1, "name": "Sports HD", ...}],
  "carousel": [...],
  "liveMatches": [...],
  "malipoPlans": [...],
  "premiumPackages": [...],
  "users": [...],
  "customerCareWhatsapp": "212600000000"
}

# Response:
{"ok": true}
```

### Public API (No Auth)

**Get Config (for viewer app):**
```bash
GET /api/v1/public/config

# Response:
{
  "channels": [...],
  "carousel": [...],
  "liveMatches": [...],
  "malipoPlans": [...],
  "premiumPackages": [...],
  "customerCareWhatsapp": "212600000000",
  "configVersion": 2,
  "configSyncedAt": 1699999999999
}
```

---

## 🆘 Troubleshooting

### "Sync failed 500" in admin app
1. Check Railway backend logs
2. Verify `DATABASE_URL` on Railway is correct
3. Verify `ADMIN_APP_PASSWORD` matches what you entered
4. Check database is running: `psql $DATABASE_URL -c "SELECT 1;"`

### "Unauthorized" or "invalid password"
1. Double-check password matches `ADMIN_APP_PASSWORD` on Railway
2. Logout and log back in
3. Reinstall admin app

### Viewer doesn't see new channels
1. Admin must sync successfully (check for green checkmark)
2. Restart viewer app
3. Check viewer logs for network errors
4. Verify viewer app has correct `API_BASE_URL` in build

### Public API returns 503
- Database not connected
- Check `DATABASE_URL` on Railway
- Check if Railway PostgreSQL service is running

---

## 📂 File Structure

```
backend/
  src/
    routes/v1/
      auth.routes.ts        ← JWT login
      admin.routes.ts       ← Config endpoints
    services/
      adminImport.ts        ← Save to DB
      publicConfig.ts       ← Load for viewers
    middleware/
      adminAuth.ts          ← Token verification

supaadmin/
  lib/
    config/
      admin_api_config.dart ← Backend URL (hardcoded)
    screens/
      login_screen.dart     ← Password input (no URL field)
      dashboard_screen.dart ← Sync button
    store/
      admin_store.dart      ← JWT + config sync

lib/
  config/
    deployment.dart         ← Backend URL (hardcoded)
  services/
    content_store.dart      ← Load public config
```

---

## ✅ Deployment Checklist

- [ ] Backend `npm run build` passes
- [ ] Railway backend service has `DATABASE_URL`
- [ ] Railway backend service has `ADMIN_APP_PASSWORD`
- [ ] Railway backend service has `JWT_SECRET`
- [ ] Admin APK built and installed
- [ ] Admin login works (password accepted)
- [ ] Admin can save/sync (no errors)
- [ ] Database has data: `psql $DATABASE_URL -c "SELECT COUNT(*) FROM channels;"`
- [ ] Viewer app fetches config: `curl https://backend/api/v1/public/config`
- [ ] Viewer APK built and installed
- [ ] Viewer shows new channels/carousel

---

## 🔐 Security Notes

- ✅ Admin password is SHA256 hashed (never stored plaintext)
- ✅ JWT tokens expire after 7 days
- ✅ No API keys exposed in admin app
- ✅ All admin endpoints require Bearer token
- ✅ Database access only through authenticated API

---

## 📞 Need Help?

1. Check `IMPLEMENTATION_COMPLETE.md` for detailed architecture
2. Run `./test-sync.sh` to verify entire flow
3. Check backend logs on Railway
4. Verify database connection: `psql $DATABASE_URL -c "SELECT NOW();"`

---

**🎉 You're ready to go! Start with Step 1 above.**
