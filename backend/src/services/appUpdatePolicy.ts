import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';

const DEFAULT_PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.ayubu.supasoka';

const APP_UPDATE_SETTING_KEYS = [
  'forceUpdateEnabled',
  'minAndroidBuild',
  'minAndroidVersion',
  'latestAndroidVersion',
  'latestAndroidBuild',
  'playStoreUrl',
] as const;

export type AppUpdatePayload = {
  updateRequired: boolean;
  minVersion: string;
  latestVersion: string;
  minBuild: number;
  latestBuild: number;
  playStoreUrl: string;
};

function parseBool(raw: string | undefined): boolean {
  const v = String(raw ?? '')
    .trim()
    .toLowerCase();
  return v === 'true' || v === '1' || v === 'yes' || v === 'on';
}

function parsePositiveInt(raw: string | undefined): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.trunc(n);
}

function parseVersionScore(raw: string): number {
  const cleaned = raw.trim().toLowerCase().replace(/^v/, '');
  const parts = cleaned.split('.');
  let score = 0;
  for (let i = 0; i < parts.length && i < 3; i += 1) {
    const part = parts[i] ?? '';
    const n = parseInt(part.replace(/[^0-9]/g, ''), 10);
    score = score * 1000 + (Number.isFinite(n) ? Math.min(Math.max(n, 0), 999) : 0);
  }
  return score;
}

function isVersionBelow(current: string, minimum: string): boolean {
  if (!minimum.trim() || !current.trim()) return false;
  return parseVersionScore(current) < parseVersionScore(minimum);
}

export async function fetchAppUpdateSettings(): Promise<Record<string, string>> {
  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured on the API service', 'NO_DATABASE');
  }
  const placeholders = APP_UPDATE_SETTING_KEYS.map((_, i) => `$${i + 1}`).join(', ');
  const setRes = await pool.query(
    `SELECT key, value FROM app_settings WHERE key IN (${placeholders})`,
    [...APP_UPDATE_SETTING_KEYS],
  );
  const settings: Record<string, string> = {};
  for (const row of setRes.rows as { key: string; value: string }[]) {
    settings[row.key] = row.value;
  }
  return settings;
}

export function buildAppUpdatePayload(
  settings: Record<string, string>,
  client?: { build?: number; version?: string },
): AppUpdatePayload {
  const minBuild = parsePositiveInt(settings.minAndroidBuild);
  const latestBuildRaw = parsePositiveInt(settings.latestAndroidBuild);
  const latestBuild = latestBuildRaw > 0 ? latestBuildRaw : minBuild;
  const minVersion = String(settings.minAndroidVersion ?? '').trim();
  const latestVersion =
    String(settings.latestAndroidVersion ?? '').trim() || minVersion;
  const playStoreUrl =
    String(settings.playStoreUrl ?? '').trim() || DEFAULT_PLAY_STORE_URL;

  const forceUpdateEnabled =
    parseBool(settings.forceUpdateEnabled) || minBuild > 0 || minVersion.length > 0;

  let updateRequired = false;
  if (forceUpdateEnabled) {
    // Missing/unknown client build counts as outdated — covers older apps without query params.
    const clientBuild =
      client != null && Number.isFinite(client.build) && (client.build ?? 0) > 0
        ? Math.trunc(client.build!)
        : 0;
    const clientVersion = String(client?.version ?? '').trim();
    if (minBuild > 0 && clientBuild < minBuild) {
      updateRequired = true;
    } else if (
      minBuild <= 0 &&
      minVersion &&
      clientVersion &&
      isVersionBelow(clientVersion, minVersion)
    ) {
      updateRequired = true;
    } else if (minBuild > 0 && !client) {
      updateRequired = true;
    }
  }

  return {
    updateRequired,
    minVersion,
    latestVersion,
    minBuild,
    latestBuild,
    playStoreUrl,
  };
}

export function readClientAppIdentity(req: {
  query: Record<string, unknown>;
  headers: Record<string, unknown>;
}): { build?: number; version?: string } {
  const buildRaw =
    req.query.appBuild ??
    req.query.build ??
    req.headers['x-app-build'] ??
    req.headers['x-supasoka-build'];
  const versionRaw =
    req.query.appVersion ??
    req.query.version ??
    req.headers['x-app-version'] ??
    req.headers['x-supasoka-version'];
  const buildParsed = Number(buildRaw);
  const build =
    Number.isFinite(buildParsed) && buildParsed > 0 ? Math.trunc(buildParsed) : undefined;
  const version = String(versionRaw ?? '').trim() || undefined;
  return { build, version };
}

/** Remove catalog payloads when the viewer must update first. */
export function stripCatalogForForcedUpdate(
  config: Record<string, unknown>,
): Record<string, unknown> {
  return {
    ...config,
    channels: [],
    carousel: [],
    liveMatches: [],
    premiumPackages: [],
    malipoPlans: [],
  };
}

/** Hide DRM keys from public config — stream URLs stay for one-tap play (EaMax-style). */
export function redactPlaybackSecretsFromConfig(
  config: Record<string, unknown>,
): Record<string, unknown> {
  const channels = config.channels;
  if (!Array.isArray(channels)) return config;
  return {
    ...config,
    channels: channels.map((entry) => {
      const row = { ...(entry as Record<string, unknown>) };
      row.clearKeyKidKey = '';
      row.licenseUrl = '';
      return row;
    }),
  };
}
