# Admin to Database Sync Flow - Technical Deep Dive

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    SUPASOKA SYSTEM FLOW                         │
└─────────────────────────────────────────────────────────────────┘

ADMIN PANEL (Flutter)          BACKEND (Node.js)        DATABASE (PostgreSQL)
─────────────────────          ─────────────────        ─────────────────────

1. LOGIN FLOW:
  Password Input
       │
       ├──→ POST /auth/admin-login ──→ SHA256 hash check
       │                                   │
       │◀────────── JWT Token ◀──────────┤
       │
    Store in SharedPrefs


2. EDIT & SAVE FLOW:
  Edit Channels
  Edit Carousel
  Edit Pricing
       │
       └──→ POST /admin/import ──→ Validate fields
           (with JWT Bearer)           │
                                      ├─→ Clear old data (TRUNCATE)
                                      │
                                      ├─→ Insert new channels
                                      │
                                      ├─→ Insert carousel slides
                                      │
                                      ├─→ Insert pricing/plans
                                      │
                                      └─→ Return {"ok": true}
                                           │
                                           └──→ Update app_settings
                                               (sync timestamp)
       │
       ◀─── {"ok": true} ◀───────────────┘
       │
    Show "Sync successful"


3. PULL LATEST FLOW:
  Admin opens app
       │
       └──→ GET /admin/export ──→ Query all tables
          (with JWT Bearer)           │
                                      ├─→ SELECT * FROM channels
                                      │
                                      ├─→ SELECT * FROM carousel_slides
                                      │
                                      ├─→ SELECT * FROM live_matches
                                      │
                                      └─→ SELECT * FROM malipo_plans
                                           │
        ◀─── Full Config ◀───────────────┘
       │
    Store locally + Display


4. VIEWER FETCH FLOW:
  Viewer app starts
       │
       └──→ GET /public/config ──→ Query all tables
          (no auth needed)            │
                                      ├─→ SELECT * FROM channels
                                      │
                                      ├─→ SELECT * FROM carousel_slides
                                      │
                                      └─→ SELECT * FROM ...
                                           │
        ◀─── Full Config ◀───────────────┘
       │
    Cache + Display channels
    Display carousel images
    Show live matches
    Display pricing tiers
```

---

## Detailed Flow: Admin Saves Channels

### Step-by-Step Execution

```
┌──────────────────────────────────────────────────────────────┐
│ Admin App: User edits channel "Sports HD"                    │
└──────────────────────────────────────────────────────────────┘

1. User interaction
   - Name: "Sports HD"
   - Category: "sports"
   - Image: "https://cdn.example.com/sports.jpg"
   - Stream URL: "https://stream.example.com/sports.m3u8"
   - DRM: "widevine"
   - Free: true

2. AdminStore.upsertChannel(channelDto) called
   └─ Adds/updates in _config.channels array
   └─ Calls _persist()

3. _persist() method:
   a) Save to SharedPreferences locally
      └─ _config.toJsonString()
      └─ prefs.setString(_prefsKey, json)
   
   b) Call _pushConfigToServer()

4. _pushConfigToServer() creates HTTP request:
   
   POST https://backend.com/api/v1/admin/import
   Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc...
   Content-Type: application/json
   
   {
     "channels": [
       {
         "id": 1,
         "name": "Sports HD",
         "cat": "sports",
         "img": "https://cdn.example.com/sports.jpg",
         "free": true,
         "viewers": "",
         "enabled": true,
         "drm": "widevine",
         "streamUrl": "https://stream.example.com/sports.m3u8"
       }
     ],
     "carousel": [...],
     "liveMatches": [...],
     "malipoPlans": [...],
     "premiumPackages": [...],
     "users": [...],
     "customerCareWhatsapp": "212600000000"
   }

5. Backend processes import:
   
   a) requireAdmin middleware
      └─ Extract Bearer token
      └─ jwt.verify(token, JWT_SECRET)
      └─ Check role === 'admin'
      └─ If valid → proceed
      └─ If invalid → 401 Unauthorized

   b) importAppConfig service
      └─ Connect to PostgreSQL
      └─ BEGIN TRANSACTION
      
      └─ TRUNCATE cascade:
         DELETE FROM carousel_slides
         DELETE FROM live_matches
         DELETE FROM malipo_plans
         DELETE FROM premium_packages
         DELETE FROM channels
      
      └─ For each channel in payload:
         - Extract fields safely:
           * channelId = asInt(ch.id) → ensures number
           * name = asString(ch.name, '') → ensures string
           * drm = asString(ch.drm, 'none') → defaults to 'none'
         
         - INSERT INTO channels:
           INSERT INTO channels (
             id, name, cat, img, free, viewers,
             stream_url, enabled, drm, clear_key_kid_key, sort_order
           ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
      
      └─ For each carousel slide:
         - Same safe extraction
         - INSERT INTO carousel_slides
      
      └─ Update app_settings:
         INSERT INTO app_settings (key, value)
         VALUES ('configSyncedAt', '1699999999999')
         ON CONFLICT (key) DO UPDATE ...
      
      └─ COMMIT TRANSACTION
      
      └─ If any error → ROLLBACK

   c) Return response:
      {"ok": true}  ← 200 OK

6. Admin app receives response:
   
   a) Parse JSON
   b) Check res.statusCode
      - 200-299 → Success
      - 401/403 → "Unauthorized — login again"
      - 503 → "Database unavailable"
      - Other → Error message
   
   c) Update UI:
      _lastSyncError = null
      Show "Sync successful" ✅

7. Admin can now verify in database:
   
   psql $DATABASE_URL -c \
     "SELECT id, name, stream_url FROM channels LIMIT 5;"
```

---

## Data Flow: Import Service Field Parsing

### Safe Field Extraction

```typescript
// Helper functions for type-safe conversion
function asString(raw: unknown, fallback = ''): string
  // Input: any
  // Output: string
  // Examples:
  //   asString('hello') → 'hello'
  //   asString(123) → '123'
  //   asString(null, 'default') → 'default'
  //   asString(undefined, '') → ''

function asInt(raw: unknown): number | null
  // Input: any
  // Output: number or null
  // Examples:
  //   asInt(42) → 42
  //   asInt('42') → 42
  //   asInt('42.7') → 42
  //   asInt('abc') → null
  //   asInt(NaN) → null

function asBool(raw: unknown, fallback: boolean): boolean
  // Input: any
  // Output: boolean
  // Examples:
  //   asBool(true) → true
  //   asBool('true') → true
  //   asBool('1') → true
  //   asBool('yes') → true
  //   asBool(false) → false
  //   asBool('false') → false
  //   asBool('0') → false
  //   asBool('no') → false
  //   asBool('random', true) → true (fallback)

function accentRgbFromDartColor(raw: unknown): number
  // Input: Dart Color.value (32-bit ARGB)
  // Output: RGB only (24-bit)
  // Examples:
  //   Input: 0xFF0000FF (alpha-red-green-blue)
  //   Output: 0x0000FF (red-green-blue only)
```

### Import Process with Safe Parsing

```typescript
// Input from admin app
const payload = {
  channels: [
    {
      id: 1,
      name: "Sports HD",
      cat: "sports",
      free: true,  // Could be string "true" or number 1
      drm: undefined,  // Missing field
      // ... other fields
    }
  ]
}

// Processing
for (const ch of payload.channels) {
  const channelId = asInt(ch.id);
  if (channelId === null) {
    throw new HttpError(400, 'Channel id must be a number', 'BAD_CHANNEL_ID');
  }
  
  // All fields safely extracted
  const result = {
    id: channelId,                           // Required number
    name: asString(ch.name, ''),             // String with fallback
    cat: asString(ch.cat, 'movies'),         // Default category
    img: asString(ch.img, ''),               // Can be empty
    free: asBool(ch.free, true),             // Flexible boolean
    viewers: asString(ch.viewers, ''),
    streamUrl: asString(ch.streamUrl || ch.url, ''),  // Try alternate field
    enabled: asBool(ch.enabled, true),       // Default enabled
    drm: asString(ch.drm, 'none'),           // Default no DRM
    clearKeyKidKey: asString(ch.clearKeyKidKey, '')
  };
  
  // Insert with prepared statement (SQL injection safe)
  await client.query(
    `INSERT INTO channels (...) VALUES ($1, $2, ...)`,
    [id, name, cat, img, free, ...]
  );
}
```

---

## Database State Transitions

### Before Admin Save
```sql
-- channels table
id  │ name           │ stream_url
────┼────────────────┼──────────────
1   │ Old Channel 1  │ http://...
2   │ Old Channel 2  │ http://...

-- carousel_slides table
id  │ title          │ channel_id
────┼────────────────┼───────────
1   │ Old Slide 1    │ 1
2   │ Old Slide 2    │ 1
```

### During Save (Transaction)
```sql
BEGIN;
TRUNCATE carousel_slides CASCADE;  -- Clears table
TRUNCATE channels CASCADE;         -- Clears table
-- New data inserted...
```

### After Save
```sql
-- channels table (NEW)
id  │ name           │ stream_url
────┼────────────────┼──────────────
1   │ Sports HD      │ http://stream.example.com/sports.m3u8
2   │ Movies Premium │ http://stream.example.com/movies.m3u8

-- carousel_slides table (NEW)
id  │ title          │ channel_id
────┼────────────────┼───────────
1   │ Live Sports    │ 1
2   │ Latest Movies  │ 2
```

---

## Error Handling & Recovery

### Sync Error Flow

```
Admin clicks Save
    ↓
Admin app makes POST to /api/v1/admin/import
    ↓
Network timeout
    ├─→ Retry attempt 1 (wait 400ms)
    ├─→ Retry attempt 2 (wait 800ms)
    ├─→ Retry attempt 3 (wait 1600ms)
    ├─→ All failed
    ↓
Set _lastSyncError = "Sync failed: <error>"
Show snackbar: "Sync failed: ..."
    ↓
User sees error message
    ↓
User can retry by clicking Sync again


If Database Unavailable:
    ↓
POST returns 503 Service Unavailable
    ↓
Set _lastSyncError = 'Database unavailable (503). Check Railway DATABASE_URL.'
    ↓
UI shows: 'Sync failed (503)...'
    ↓
Admin sees: "Check Railway DATABASE_URL"


If Unauthorized (JWT expired):
    ↓
POST returns 401 Unauthorized
    ↓
Set _lastSyncError = 'Unauthorized — login again with your admin password.'
    ↓
UI shows: "Unauthorized"
    ↓
Admin must click "Log in again" and re-enter password
```

---

## JWT Token Lifecycle

```
┌──────────────────────────────────────────────────────────┐
│ JWT TOKEN LIFECYCLE                                      │
└──────────────────────────────────────────────────────────┘

1. LOGIN - Token Created
   POST /auth/admin-login
   Body: {"password": "MySecurePassword123"}
   
   Backend:
   - Hash password with SHA256
   - Compare with ADMIN_APP_PASSWORD
   - If match: issue JWT
     jwt.sign({
       sub: 'supaadmin',
       role: 'admin'
     }, JWT_SECRET, {
       expiresIn: '7d'
     })
   
   Response: {"ok": true, "token": "eyJ0eXAiOiJKV1QiLCJhbGc..."}

2. TOKEN STORED - Saved in SharedPreferences
   Admin app stores in SharedPreferences with key '_prefsJwt'
   (Persists across app restarts)

3. TOKEN USED - Sent with every admin request
   GET /admin/export
   Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc...
   
   POST /admin/import
   Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGc...

4. TOKEN VERIFIED - Backend checks signature
   middleware/adminAuth.ts requireAdmin():
   - Extract token from Authorization header
   - jwt.verify(token, JWT_SECRET)
   - If valid → proceed
   - If invalid/expired → 401 Unauthorized

5. TOKEN EXPIRY - After 7 days
   - Token becomes invalid
   - Request returns 401
   - Admin must log in again
   - Admin app shows: "Unauthorized — login again"

6. LOGOUT - Token Cleared
   Admin clicks logout
   - Delete from SharedPreferences
   - Set _jwt = ''
   - User returned to login screen
```

---

## Public API Cache Strategy

### Viewer App Caching

```
App Start
  │
  ├─→ Load cached config from SharedPreferences
  │   (if first launch, cache is empty)
  │
  ├─→ Fetch /api/v1/public/config from backend
  │   With query params to prevent browser cache:
  │   ?_=<timestamp>&r=<microseconds>
  │
  ├─→ If 200 OK:
  │   - Parse JSON
  │   - Cache in SharedPreferences
  │   - Display channels, carousel, pricing
  │
  ├─→ If 404 Not Found:
  │   - Show error: "Backend URL is wrong"
  │   - Display last cached config if available
  │
  ├─→ If 503 Unavailable:
  │   - Show error: "Database unavailable"
  │   - Display last cached config if available
  │
  ├─→ If Network Error:
  │   - Show error: "No internet"
  │   - Display last cached config if available
  │
  └─→ Ready to display
```

### Cache Invalidation

```
When admin syncs new config:
  1. Data written to database
  2. app_settings['configSyncedAt'] = current timestamp
  3. Viewer app sees new configSyncedAt in public API
  4. If timestamp changed → re-fetch data
```

---

## Data Consistency Guarantees

### ACID Compliance

```
Import Transaction:
┌─────────────────────────────────────┐
│ BEGIN                               │
├─────────────────────────────────────┤
│ TRUNCATE cascade (atomic)           │
│ ├─ channels                         │
│ ├─ carousel_slides                  │
│ ├─ live_matches                     │
│ ├─ malipo_plans                     │
│ └─ premium_packages                 │
├─────────────────────────────────────┤
│ INSERT new channels                 │
│ INSERT new carousel_slides          │
│ INSERT new live_matches             │
│ INSERT new malipo_plans             │
│ INSERT new premium_packages         │
├─────────────────────────────────────┤
│ UPDATE app_settings (sync timestamp)│
├─────────────────────────────────────┤
│ COMMIT                              │
│ (All or nothing - no partial state) │
└─────────────────────────────────────┘

If any INSERT fails:
  ROLLBACK
  Database returns to previous state
  Admin app receives error
  No partial/corrupted data
```

---

## Monitoring & Debugging

### Check Data Flow

```bash
# 1. Verify backend is responding
curl -v https://backend.com/api/v1/public/config

# 2. Test admin login
curl -X POST https://backend.com/api/v1/auth/admin-login \
  -H "Content-Type: application/json" \
  -d '{"password": "MyPassword"}'

# 3. Check database directly
psql $DATABASE_URL -c "SELECT COUNT(*) FROM channels;"

# 4. View app_settings (includes sync timestamp)
psql $DATABASE_URL -c "SELECT * FROM app_settings;"

# 5. Check recent changes
psql $DATABASE_URL -c \
  "SELECT id, name, updated_at FROM channels ORDER BY updated_at DESC LIMIT 5;"
```

### Common Issues & Solutions

```
Issue: "Sync failed 500"
─────────────────────────
Causes:
  1. Database connection down
  2. Invalid field in import payload
  3. Query execution error

Debug:
  - Check backend logs on Railway
  - Verify DATABASE_URL
  - Test database: psql $DATABASE_URL -c "SELECT 1;"
  - Check field types match schema

Issue: "Unauthorized" immediately after login
─────────────────────────────────────────────
Causes:
  1. JWT_SECRET changed (old tokens invalid)
  2. Password incorrect (hash mismatch)
  3. Token corrupted

Debug:
  - Verify ADMIN_APP_PASSWORD on Railway
  - Verify JWT_SECRET hasn't changed
  - Clear app cache, log in again
  - Check token wasn't corrupted

Issue: Admin saves but viewer doesn't see changes
──────────────────────────────────────────────────
Causes:
  1. Sync didn't complete (check for error in admin)
  2. Viewer didn't fetch new config (cached old data)
  3. Viewer using wrong API base URL

Debug:
  - Check admin shows "Sync successful"
  - Restart viewer app
  - Check public config: curl .../api/v1/public/config
  - Verify API_BASE_URL in viewer build
```

---

This completes the technical deep-dive of the admin-to-database sync architecture.
