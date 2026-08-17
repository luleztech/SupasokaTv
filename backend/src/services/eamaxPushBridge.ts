import { env } from '../config/env';

export type EamaxMirrorInput = {
  title: string;
  body: string;
  scope: 'broadcast' | 'user';
  /** all | premium | free — maps to FCM topics on the partner side */
  target?: string;
  externalId?: string;
  /** broadcast | reminder — partners may drop reminders */
  kind?: 'broadcast' | 'reminder';
};

export type EamaxMirrorResult = {
  ok: boolean;
  skipped?: boolean;
  scope?: string;
  delivered?: boolean;
  messageId?: string;
  reason?: string;
  error?: string;
  partner?: string;
};

const BRIDGE_PATH = '/api/partner/supa-push';
const REQUEST_TIMEOUT_MS = 20_000;

type PartnerConfig = {
  name: string;
  baseUrl: string;
  secret: string;
};

function partners(): PartnerConfig[] {
  const list: PartnerConfig[] = [];
  if (env.eamaxApiBaseUrl.trim() && env.eamaxBridgeSecret.trim()) {
    list.push({
      name: 'eamax',
      baseUrl: env.eamaxApiBaseUrl.trim(),
      secret: env.eamaxBridgeSecret.trim(),
    });
  }
  if (env.jamboplusApiBaseUrl.trim() && env.jamboplusBridgeSecret.trim()) {
    list.push({
      name: 'jamboplus',
      baseUrl: env.jamboplusApiBaseUrl.trim(),
      secret: env.jamboplusBridgeSecret.trim(),
    });
  }
  if (env.leotenaApiBaseUrl.trim() && env.leotenaBridgeSecret.trim()) {
    list.push({
      name: 'leotena',
      baseUrl: env.leotenaApiBaseUrl.trim(),
      secret: env.leotenaBridgeSecret.trim(),
    });
  }
  return list;
}

async function mirrorToPartner(
  partner: PartnerConfig,
  input: EamaxMirrorInput,
): Promise<EamaxMirrorResult> {
  const title = input.title.trim();
  const message = input.body.trim();
  if (!title || !message) {
    return { ok: false, error: 'title and body are required', partner: partner.name };
  }

  // JamboPlus / Leotena only want intentional broadcasts. User/expired
  // reminders use Supasoka public IDs and must never fan out to every device.
  if ((partner.name === 'jamboplus' || partner.name === 'leotena') && input.scope === 'user') {
    return {
      ok: true,
      skipped: true,
      reason: 'user_scope_not_mirrored',
      partner: partner.name,
      scope: input.scope,
      delivered: false,
    };
  }
  if ((partner.name === 'jamboplus' || partner.name === 'leotena') && input.kind === 'reminder') {
    return {
      ok: true,
      skipped: true,
      reason: 'reminder_not_mirrored',
      partner: partner.name,
      scope: input.scope,
      delivered: false,
    };
  }

  const base = partner.baseUrl.replace(/\/+$/, '');
  const url = `${base}${BRIDGE_PATH}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const body: Record<string, string> = {
      title,
      message,
      scope: input.scope,
      target: (input.target || 'all').trim() || 'all',
      kind: input.kind || (input.scope === 'user' ? 'reminder' : 'broadcast'),
    };
    if (input.scope === 'user' && input.externalId?.trim()) {
      body.externalId = input.externalId.trim();
    }

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Partner-Secret': partner.secret,
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
        `${partner.name} bridge HTTP ${res.status}`;
      console.warn(`[${partner.name} bridge]`, errMsg);
      return { ok: false, error: errMsg, partner: partner.name };
    }

    return {
      ok: true,
      partner: partner.name,
      scope: typeof parsed.scope === 'string' ? parsed.scope : input.scope,
      delivered:
        typeof parsed.delivered === 'boolean' ? parsed.delivered : undefined,
      messageId:
        typeof parsed.messageId === 'string' ? parsed.messageId : undefined,
      reason: typeof parsed.reason === 'string' ? parsed.reason : undefined,
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.warn(`[${partner.name} bridge] request failed:`, msg);
    return { ok: false, error: msg, partner: partner.name };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Forward SupaAdmin push to EaMax + JamboPlus + Leotena (when configured).
 * Failures are logged and returned, not thrown.
 */
export async function mirrorPushToEamax(input: EamaxMirrorInput): Promise<EamaxMirrorResult> {
  const configured = partners();
  if (configured.length === 0) {
    return { ok: true, skipped: true, reason: 'no_push_partners_configured' };
  }

  const results = await Promise.all(configured.map((p) => mirrorToPartner(p, input)));
  const failed = results.filter((r) => !r.ok);
  const ok = results.some((r) => r.ok) || failed.length === 0;

  // Prefer jamboplus result details when present, else first result.
  const primary: EamaxMirrorResult =
    results.find((r) => r.partner === 'jamboplus' && r.ok) ||
    results.find((r) => r.ok) ||
    results[0] || { ok: false, error: 'no partner results' };

  if (failed.length) {
    console.warn(
      '[push partners]',
      failed.map((f) => `${f.partner}: ${f.error}`).join('; '),
    );
  }

  return {
    ...primary,
    ok,
    reason:
      primary.reason ||
      (failed.length ? failed.map((f) => f.error).join('; ') : undefined),
  };
}

export function checkEamaxBridgeConfiguration(): { ok: boolean; message: string } {
  const configured = partners();
  if (configured.length === 0) {
    return {
      ok: false,
      message:
        'No push partners configured. Set EAMAX_API_BASE_URL + EAMAX_BRIDGE_SECRET, JAMBOPLUS_API_BASE_URL + JAMBOPLUS_BRIDGE_SECRET, and/or LEOTENA_API_BASE_URL + LEOTENA_BRIDGE_SECRET.',
    };
  }
  return {
    ok: true,
    message: `Push partners: ${configured.map((p) => p.name).join(', ')}`,
  };
}
