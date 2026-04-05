/// Public HTTPS origin for the Node **API** (no trailing slash, no `:port`).
/// The mobile app loads `/api/v1/public/config` from here. Match your Railway service
/// **Networking** URL (e.g. one service with root directory `backend/`).
///
/// Override: `--dart-define=API_BASE_URL=https://…`
const String kRailwayApiBaseUrl = 'https://supasokatv-production.up.railway.app';
