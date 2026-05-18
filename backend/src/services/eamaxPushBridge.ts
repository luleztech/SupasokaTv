import { env } from '../config/env';

export type EamaxMirrorInput = {
  title: string;
  body: string;
  scope: 'broadcast' | 'user';
  externalId?: string;
};

export type EamaxMirrorResult = {
  ok: boolean;
  skipped?: boolean;
  scope?: string;
  delivered?: boolean;
  messageId?: string;
  reason?: string;
  error?: string;
};

const BRIDGE_PATH = '/api/partner/supa-push';
const REQUEST_TIMEOUT_MS = 20_000;

function bridgeConfigured(): boolean {
  return Boolean(env.eamaxApiBaseUrl.trim() && env.eamaxBridgeSecret.trim());
}

/**
 * Forward SupaAdmin push to EaMax FCM (topic all_users or per-user token).
 * Non-blocking for Supasoka sends: failures are logged and returned, not thrown.
 */
export async function mirrorPushToEamax(input: EamaxMirrorInput): Promise<EamaxMirrorResult> {
  if (!bridgeConfigured()) {
    return { ok: true, skipped: true, reason: 'eamax_bridge_not_configured' };
  }

  const title = input.title.trim();
  const message = input.body.trim();
  if (!title || !message) {
    return { ok: false, error: 'title and body are required' };
  }

  const base = env.eamaxApiBaseUrl.replace(/\/+$/, '');
  const url = `${base}${BRIDGE_PATH}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const body: Record<string, string> = {
      title,
      message,
      scope: input.scope,
    };
    if (input.scope === 'user' && input.externalId?.trim()) {
      body.externalId = input.externalId.trim();
    }

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Partner-Secret': env.eamaxBridgeSecret,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    const text = await res.text();
    let parsed: Record<string, unknown> = {};
    if (text) {
      try {
        parsed = JSON.parse(text) as Record<string, unknown>;
      } catch {
        parsed = { raw: text };
      }
    }

    if (!res.ok) {
      const errMsg =
        (typeof parsed.error === 'string' && parsed.error) ||
        `EaMax bridge HTTP ${res.status}`;
      console.warn('[EaMax bridge]', errMsg);
      return { ok: false, error: errMsg };
    }

    return {
      ok: true,
      scope: typeof parsed.scope === 'string' ? parsed.scope : input.scope,
      delivered:
        typeof parsed.delivered === 'boolean' ? parsed.delivered : undefined,
      messageId:
        typeof parsed.messageId === 'string' ? parsed.messageId : undefined,
      reason: typeof parsed.reason === 'string' ? parsed.reason : undefined,
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.warn('[EaMax bridge] request failed:', msg);
    return { ok: false, error: msg };
  } finally {
    clearTimeout(timer);
  }
}

export function checkEamaxBridgeConfiguration(): { ok: boolean; message: string } {
  if (!bridgeConfigured()) {
    return {
      ok: false,
      message:
        'EaMax mirror not configured. Set EAMAX_API_BASE_URL and EAMAX_BRIDGE_SECRET (must match EaMax SUPA_EAMAX_BRIDGE_SECRET).',
    };
  }
  return { ok: true, message: 'EaMax push mirror is configured.' };
}
