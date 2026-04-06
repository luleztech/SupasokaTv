# Supasoka Admin-Backend Sync Architecture

## Overview
The admin app (`SupaAdmin`) now saves all configuration **exclusively to the Railway PostgreSQL database** via a backend Node.js API. The admin app no longer exposes API URL inputs or manages cloud settings—everything is backend-driven.

## Architecture

### 1. Admin App (`supaadmin/`)
**Flow:**
```
SupaAdmin Login Screen
  ↓
User enters password (no API URL field)
  ↓
POST /api/v1/auth/admin-login (password) → JWT token
  ↓
Token stored in SharedPreferences
  ↓
Admin makes edits (channels, carousel, pricing, etc.)
  ↓
POST /api/v1/admin/import (JWT Bearer token)
  ↓
Backend validates, stores in PostgreSQL
```

**Key Files:**
- `supaadmin/lib/config/admin_api_config.dart` - Hardcoded build-time API base URL
- `supaadmin/lib/screens/login_screen.dart` - JWT login flow (no API URL input)
- `supaadmin/lib/store/admin_store.dart` - Config sync and JWT token management
- `supaadmin/lib/screens/dashboard_screen.dart` - Sync button & status display

**Build URL:**
- Default: `https://supasokatv-production.up.railway.app`
- Override: `flutter build apk --dart-define=API_BASE_URL=<your-backend-url>`

### 2. Backend API (`backend/`)
**Endpoints:**

| Method | Endpoint | Auth | Purpose |
|--------|----------|------|---------|
| POST | `/api/v1/auth/admin-login` | Password | Admin login → JWT token |
| GET | `/api/v1/admin/export` | JWT Bearer | Export full config from DB |
| POST | `/api/v1/admin/import` | JWT Bearer | Save config to DB |
| GET | `/api/v1/admin/users` | JWT Bearer | List users from DB |
| DELETE | `/api/v1/admin/users/:id` | JWT Bearer | Delete user from DB |

**Key Files:**
- `backend/src/routes/v1/auth.routes.ts` - JWT token generation
- `backend/src/routes/v1/admin.routes.ts` - Admin config endpoints
- `backend/src/services/adminImport.ts` - DB persist logic with safe parsing
- `backend/src/middleware/adminAuth.ts` - JWT verification + legacy API key fallback
- `backend/src/config/env.ts` - Environment variables

**Environment Variables (Railway):**
```
DATABASE_URL          → PostgreSQL connection
ADMIN_APP_PASSWORD    → Password for admin login (hashed with SHA256)
JWT_SECRET            → Secret for signing JWT tokens
ADMIN_API_KEY         → (legacy, for backward compatibility)
```

### 3. Public Viewer App (`lib/`)
**Flow:**
```
Viewer app starts
  ↓
GET /api/v1/public/config
  ↓
Parse channels, carousel, live matches, malipo plans, premium packages
  ↓
Display to user
```

**Synced Data:**
- Channels (name, stream URL, DRM, etc.)
- Carousel slides (badge, title, image, channel link)
- Live matches (title, sport icon, image)
- Malipo plans (pricing, colors, badges)
- Premium packages (features, pricing)
- Customer care WhatsApp number
- App settings (version, sync timestamp)

## Admin App Setup & Build

### Prerequisites
1. Backend running on Railway with env vars configured
2. Flutter 3.11.4+ installed
3. Android SDK for APK build

### Steps

#### 1. Verify Backend Environment
```bash
# Check Railway service environment variables:
# - DATABASE_URL=postgres://...
# - ADMIN_APP_PASSWORD=<your-password>
# - JWT_SECRET=<random-secret>
```

#### 2. Build SupaAdmin APK
```bash
cd supaadmin
flutter clean
flutter pub get

# Option A: Use default API URL (https://supasokatv-production.up.railway.app)
flutter build apk --release

# Option B: Override API URL
flutter build apk --release --dart-define=API_BASE_URL=https://your-backend.com
```

**APK Location:** `supaadmin/build/app/outputs/flutter-apk/app-release.apk`

#### 3. Install & Test
```bash
# Connect Android device via ADB
adb install supaadmin/build/app/outputs/flutter-apk/app-release.apk

# Open app
# Enter password → Get JWT
# Edit channels/carousel/pricing
# Click "Sync" button (dashboard)
# Check for "Sync successful" message
```

## Database Schema

**Tables (auto-created by migrations):**
- `channels` - Broadcast channels
- `carousel_slides` - Home carousel images
- `live_matches` - Sports/events
- `malipo_plans` - Mobile payment pricing
- `premium_packages` - Subscription plans
- `users` - Registered viewers + premium status
- `app_settings` - Global config (WhatsApp, version, sync time)

**Example: channels table**
```sql
CREATE TABLE channels (
  id INTEGER PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  cat VARCHAR(100),
  img TEXT,
  free BOOLEAN DEFAULT true,
  viewers VARCHAR(255),
  stream_url TEXT,
  enabled BOOLEAN DEFAULT true,
  drm VARCHAR(50) DEFAULT 'none',
  clear_key_kid_key TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);
```

## Troubleshooting

### "Sync failed 500" error
**Cause:** Backend or database error
**Check:**
```bash
# 1. Backend logs
# Check Railway log stream for errors

# 2. Database connection
# Verify DATABASE_URL on Railway

# 3. Admin middleware
# Ensure JWT_SECRET and ADMIN_APP_PASSWORD are set

# 4. Sample test sync
curl -X POST https://your-backend.com/api/v1/admin/import \
  -H "Authorization: Bearer <jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "channels": [],
    "carousel": [],
    "liveMatches": [],
    "malipoPlans": [],
    "premiumPackages": [],
    "users": [],
    "customerCareWhatsapp": "212600000000"
  }'
```

### Admin app shows "Unauthorized"
**Cause:** JWT token expired or wrong password
**Fix:**
1. Log in again in admin app
2. Verify `ADMIN_APP_PASSWORD` on Railway matches what you entered
3. Verify `JWT_SECRET` is set on Railway

### Viewer app doesn't see new channels
**Cause:** Admin didn't sync, or public API not responding
**Fix:**
1. In admin app, click "Sync" button
2. Wait for "Sync successful" message
3. Restart viewer app
4. Check viewer app logs for network errors

### Database not receiving data
**Cause:** Import service not writing properly
**Check:**
```bash
# Query database directly
psql $DATABASE_URL -c "SELECT COUNT(*) FROM channels;"
psql $DATABASE_URL -c "SELECT COUNT(*) FROM carousel_slides;"
```

## Security Notes

1. **Admin Password:** Use strong, unique password; set as `ADMIN_APP_PASSWORD` on Railway
2. **JWT Secret:** Use 32+ character random string; set as `JWT_SECRET` on Railway
3. **No API Keys in App:** Admin app doesn't store API keys—only JWT tokens are ephemeral
4. **Database:** Access only via authenticated API endpoints
5. **Tokens Expire:** JWT tokens expire after 7 days; user must log in again

## API Request Examples

### Login
```bash
curl -X POST https://backend.com/api/v1/auth/admin-login \
  -H "Content-Type: application/json" \
  -d '{"password": "mypassword"}'

# Response:
# {"ok": true, "token": "eyJ..."}
```

### Export Config
```bash
curl -X GET https://backend.com/api/v1/admin/export \
  -H "Authorization: Bearer eyJ..."

# Response: {"ok": true, "channels": [...], "carousel": [...], ...}
```

### Import Config
```bash
curl -X POST https://backend.com/api/v1/admin/import \
  -H "Authorization: Bearer eyJ..." \
  -H "Content-Type: application/json" \
  -d '{
    "channels": [{"id": 1, "name": "Sports", ...}],
    "carousel": [...],
    ...
  }'

# Response: {"ok": true}
```

## Deployment Checklist

- [ ] Backend `npm run build` succeeds
- [ ] Railway env vars set: `DATABASE_URL`, `ADMIN_APP_PASSWORD`, `JWT_SECRET`
- [ ] Database migrations applied (schema exists)
- [ ] Admin app built and installed
- [ ] Admin login works (test password)
- [ ] Dashboard sync button works (no 500 errors)
- [ ] Viewer app fetches `/api/v1/public/config` successfully
- [ ] New channels appear in viewer after admin sync
- [ ] Carousel images display in viewer

## Next Steps

1. Ensure backend is running and accessible
2. Set Railway env vars
3. Build SupaAdmin APK
4. Test admin login and sync
5. Deploy viewer app with correct public API URL
6. Monitor sync success in admin dashboard
