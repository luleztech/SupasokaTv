import { getPool } from '../db/pool';
import { HttpError } from '../middleware/errorHandler';
import { playbackHeadersForStreamUrl } from '../lib/cdnTokenHeaders';
import { relayPlaybackUrl } from './streamRelay';
import {
  buildAppUpdatePayload,
  fetchAppUpdateSettings,
  readClientAppIdentity,
} from './appUpdatePolicy';
import { getUserPremiumRecord, isValidPublicUserId, registerPublicUser, isPremiumUntilActive, isUserPremiumRevokeLocked } from './userDirectory';
import { reconcilePremiumForUser } from './unifiedPayments';

export type PlaybackSessionPayload = {
  streamUrl: string;
  drm: string;
  clearKeyKidKey: string;
  licenseUrl: string;
  free: boolean;
  audioLanguage: string;
  playbackHeaders: Record<string, string>;
};

export type PlaybackResolveResult =
  | { ok: true; session: PlaybackSessionPayload }
  | {
      ok: false;
      code: 'UPDATE_REQUIRED' | 'PREMIUM_REQUIRED' | 'CHANNEL_NOT_FOUND' | 'CHANNEL_DISABLED';
      updateRequired?: boolean;
      premiumRequired?: boolean;
    };

function isPremiumActive(premiumUntilMs: number | null): boolean {
  return isPremiumUntilActive(premiumUntilMs);
}

function apiOriginFromRequest(req: {
  headers: Record<string, unknown>;
}): string {
  const proto = String(req.headers['x-forwarded-proto'] ?? 'https').split(',')[0]!.trim();
  const host = String(req.headers['x-forwarded-host'] ?? req.headers.host ?? '')
    .split(',')[0]!
    .trim();
  return `${proto}://${host}`;
}

function normalizeChannelAudioLanguage(raw: unknown): string {
  const r = String(raw ?? '').trim().toLowerCase();
  if (r === 'en' || r.startsWith('en-') || r === 'english' || r === 'eng') return 'en';
  if (r === 'sw' || r.startsWith('sw-') || r === 'swahili' || r === 'kiswahili' || r === 'swa') return 'sw';
  return 'sw';
}

/** Authoritative live playback — never expose stream URLs in public config. */
export async function resolvePlaybackForChannel(
  channelId: number,
  userId: string,
  req: { query: Record<string, unknown>; headers: Record<string, unknown> },
): Promise<PlaybackResolveResult> {
  const updateSettings = await fetchAppUpdateSettings();
  const client = readClientAppIdentity(req);
  const appUpdate = buildAppUpdatePayload(updateSettings, client);
  if (appUpdate.updateRequired) {
    return { ok: false, code: 'UPDATE_REQUIRED', updateRequired: true };
  }

  const pool = getPool();
  if (!pool) {
    throw new HttpError(503, 'DATABASE_URL is not configured on the API service', 'NO_DATABASE');
  }

  const chRes = await pool.query<{
    id: number;
    free: boolean;
    enabled: boolean;
    stream_url: string;
    drm: string;
    clear_key_kid_key: string;
    audio_language: string;
  }>(
    `SELECT id, free, enabled, stream_url, drm, clear_key_kid_key, audio_language
     FROM channels WHERE id = $1`,
    [channelId],
  );
  const row = chRes.rows[0];
  if (!row) {
    return { ok: false, code: 'CHANNEL_NOT_FOUND' };
  }
  if (!row.enabled) {
    return { ok: false, code: 'CHANNEL_DISABLED' };
  }

  const streamUrl = String(row.stream_url ?? '').trim();
  if (!streamUrl) {
    return { ok: false, code: 'CHANNEL_DISABLED' };
  }

  if (!row.free) {
    const trimmedUser = String(userId ?? '').trim();
    if (!trimmedUser) {
      return { ok: false, code: 'PREMIUM_REQUIRED', premiumRequired: true };
    }
    if (isValidPublicUserId(trimmedUser)) {
      await registerPublicUser({ publicId: trimmedUser, profileUsername: trimmedUser });
    }
    const premium = await getUserPremiumRecord(trimmedUser);
    if (!isPremiumActive(premium.premiumUntilMs)) {
      if (!(await isUserPremiumRevokeLocked(trimmedUser))) {
        const reconciled = await reconcilePremiumForUser(trimmedUser);
        if (!isPremiumActive(reconciled)) {
          return { ok: false, code: 'PREMIUM_REQUIRED', premiumRequired: true };
        }
      } else {
        return { ok: false, code: 'PREMIUM_REQUIRED', premiumRequired: true };
      }
    }
  }

  return {
    ok: true,
    session: {
      streamUrl:
        relayPlaybackUrl(apiOriginFromRequest(req), channelId, streamUrl) ?? streamUrl,
      drm: String(row.drm ?? 'none'),
      clearKeyKidKey: String(row.clear_key_kid_key ?? ''),
      licenseUrl: '',
      free: row.free === true,
      audioLanguage: normalizeChannelAudioLanguage(row.audio_language),
      playbackHeaders: playbackHeadersForStreamUrl(streamUrl),
    },
  };
}

export async function assertSupportedAppClient(req: {
  query: Record<string, unknown>;
  headers: Record<string, unknown>;
}): Promise<{ updateRequired: boolean; appUpdate: ReturnType<typeof buildAppUpdatePayload> }> {
  const updateSettings = await fetchAppUpdateSettings();
  const client = readClientAppIdentity(req);
  const appUpdate = buildAppUpdatePayload(updateSettings, client);
  return { updateRequired: appUpdate.updateRequired, appUpdate };
}
