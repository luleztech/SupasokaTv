import { createHmac, timingSafeEqual } from 'crypto';
import { env } from '../config/env';
import { HttpError } from '../middleware/errorHandler';
import { logger } from '../lib/logger';
import {
  detectTzMobileNetwork,
  formatPhoneToIntl255,
  toLocal0Digits,
} from '../lib/tzPhone';

const AURAX_API_BASE = (process.env.AURAXPAY_BASE_URL || 'https://api.auraxpay.net/v1').replace(
  /\/$/,
  '',
);
const AURAX_HTTP_TIMEOUT_MS = 22_000;
const AURAX_MIN_AMOUNT = 500;

const AURAX_PAID = new Set(['SUCCESS', 'SUCCESSFUL', 'COMPLETED', 'PAID', 'SETTLED', 'CONFIRMED']);

export function isAuraxConfigured(): boolean {
  return Boolean(env.auraxPayApiKey.trim());
}

export function ensureAuraxConfigured(): void {
  if (!isAuraxConfigured()) {
    throw new HttpError(503, 'Aurax Pay haijasanidi kwenye seva', 'AURAX_NOT_CONFIGURED');
  }
}

/** Aurax channel enum from TZ MSISDN (EaMax mapping — 079 is Vodacom M-Pesa). */
export function resolveAuraxChannelFromPhone(local0: string): string {
  const p = toLocal0Digits(local0);
  const network = detectTzMobileNetwork(p);
  if (network === 'halotel') return 'HALOPESA';
  if (network === 'tigo_yas') return 'TIGO_PESA';
  if (network === 'airtel') return 'AIRTEL_MONEY';
  if (network === 'vodacom' || network === 'mo_mobile') return 'MPESA';
  if (/^07[4569]/.test(p)) return 'MPESA';
  return 'MPESA';
}

export function auraxChannelCandidates(local0: string): string[] {
  const p = toLocal0Digits(local0);
  const network = detectTzMobileNetwork(p);
  switch (network) {
    case 'airtel':
      return ['AIRTEL_MONEY'];
    case 'halotel':
      // Halopesa 061 / 062 / 063
      return ['HALOPESA'];
    case 'tigo_yas':
      // Mixx by Yas / Tigo including 070 and 071
      return ['TIGO_PESA'];
    case 'vodacom':
    case 'mo_mobile':
      return ['MPESA'];
    default:
      return [resolveAuraxChannelFromPhone(local0)];
  }
}

/** Aurax requires E.164 `+255XXXXXXXXX` only (rejects bare 255… and local 0…). */
export function formatPhoneForAuraxPayApi(local0: string): string {
  const intl = formatPhoneToIntl255(toLocal0Digits(local0));
  const digits = intl.replace(/\D/g, '');
  const national = digits.startsWith('255') ? digits.slice(3, 12) : digits.slice(0, 9);
  return national ? `+255${national}` : `+${intl.replace(/^\+/, '')}`;
}

export function auraxPhoneCandidates(local0: string): string[] {
  const e164 = formatPhoneForAuraxPayApi(local0);
  return e164.startsWith('+255') && e164.length >= 13 ? [e164] : [];
}

function auraxHeaders(): Record<string, string> {
  return {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    'x-api-key': env.auraxPayApiKey.trim(),
  };
}

async function auraxFetchJson(
  path: string,
  init: RequestInit,
): Promise<{ response: Response; data: Record<string, unknown> }> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), AURAX_HTTP_TIMEOUT_MS);
  try {
    const res = await fetch(`${AURAX_API_BASE}${path}`, { ...init, signal: ctrl.signal });
    const text = await res.text();
    let data: Record<string, unknown> = {};
    try {
      data = (JSON.parse(text) as Record<string, unknown>) ?? {};
    } catch {
      data = { status: 'error', message: text.slice(0, 200) };
    }
    return { response: res, data };
  } finally {
    clearTimeout(t);
  }
}

export function isAuraxInitiateSuccess(
  auraxData: Record<string, unknown> | null | undefined,
  httpResponse: Response,
): boolean {
  if (!auraxData || typeof auraxData !== 'object') return false;
  if (auraxData.success === true && auraxData.transaction) return true;
  const tx = auraxData.transaction;
  if (tx && typeof tx === 'object') {
    const row = tx as Record<string, unknown>;
    if (row.id || row.reference) return httpResponse.ok !== false;
  }
  return false;
}

export function extractAuraxTransactionRef(auraxData: Record<string, unknown>): string {
  const tx = (auraxData.transaction ?? auraxData.data ?? auraxData) as Record<string, unknown>;
  if (!tx || typeof tx !== 'object') return '';
  return String(tx.id ?? tx.reference ?? tx.paymentId ?? tx.payment_id ?? '').trim();
}

export async function tryCreateAuraxOrder(args: {
  localPhone: string;
  amountTzs: number;
  buyerName: string;
  buyerEmail: string;
  publicId: string;
  planId: string;
  clientOrderId: string;
}): Promise<{
  ok: boolean;
  orderId: string;
  message: string;
  raw: Record<string, unknown>;
  errorMessage?: string;
}> {
  ensureAuraxConfigured();
  const amount = Math.max(AURAX_MIN_AMOUNT, Math.trunc(Number(args.amountTzs) || 0));
  const channels = auraxChannelCandidates(args.localPhone);
  const callbackUrl =
    env.auraxPayWebhookUrl.trim() ||
    `${env.publicBaseUrl.replace(/\/$/, '')}/api/v1/public/aurax/webhook`;

  // Aurax: single E.164 +255… phone + correct channel (HALOPESA / TIGO_PESA / …).
  const preferredPhone = formatPhoneForAuraxPayApi(args.localPhone);
  const tryList: { channel: string; phone: string }[] = [];
  const seen = new Set<string>();
  const pushCombo = (channel: string, phone: string) => {
    const key = `${channel}|${phone}`;
    if (seen.has(key)) return;
    seen.add(key);
    tryList.push({ channel, phone });
  };
  const phones = auraxPhoneCandidates(args.localPhone);
  const phone = phones[0] || preferredPhone;
  for (const ch of channels) {
    pushCombo(ch, phone);
  }
  if (tryList.length === 0) {
    pushCombo(resolveAuraxChannelFromPhone(args.localPhone), preferredPhone);
  }
  const limitedTryList = tryList.slice(0, 2);

  let lastFailResult: {
    ok: false;
    orderId: string;
    message: string;
    raw: Record<string, unknown>;
    errorMessage?: string;
  } = {
    ok: false,
    orderId: '',
    message: 'Failed to start Aurax Pay',
    raw: {},
    errorMessage: 'Hatukuweza kuanzisha malipo. Jaribu tena.',
  };

  for (let i = 0; i < limitedTryList.length; i++) {
    const combo = limitedTryList[i]!;
    const payload = {
      amount,
      currency: 'TZS',
      channel: combo.channel,
      buyerPhone: combo.phone,
      buyerName: args.buyerName,
      buyerEmail: args.buyerEmail,
      description: `Supasoka ${args.planId}`,
      callbackUrl,
      metadata: {
        orderId: args.clientOrderId,
        public_id: args.publicId,
        external_id: args.publicId,
        plan_id: args.planId,
      },
    };

    logger.info(
      { channel: combo.channel, phone: combo.phone, amount, clientOrderId: args.clientOrderId },
      'aurax_create_begin',
    );

    try {
      const { response, data } = await auraxFetchJson('/payments', {
        method: 'POST',
        headers: auraxHeaders(),
        body: JSON.stringify(payload),
      });
      if (!isAuraxInitiateSuccess(data, response)) {
        const msg = String(data.message ?? data.error ?? 'Failed to start Aurax Pay').trim();
        logger.warn({ channel: combo.channel, msg, status: response.status }, 'aurax_create_failed');
        lastFailResult = {
          ok: false,
          orderId: '',
          message: msg,
          raw: data,
          errorMessage:
            'Hatukuweza kutuma ombi la malipo kwenye simu yako. Hakikisha nambari ni sahihi, una salio, kisha jaribu tena.',
        };
        continue;
      }
      const gatewayRef = extractAuraxTransactionRef(data);
      if (!gatewayRef) {
        lastFailResult = {
          ok: false,
          orderId: '',
          message: 'Aurax Pay did not return a transaction id',
          raw: data,
          errorMessage: 'Hatukuweza kuanzisha malipo. Jaribu tena.',
        };
        continue;
      }
      logger.info({ orderId: gatewayRef, channel: combo.channel }, 'aurax_create_ok');
      return {
        ok: true,
        orderId: gatewayRef,
        message: String(
          data.message ??
            'Ombi limetumwa. Angalia simu yako na uingize PIN ya malipo.',
        ),
        raw: data,
      };
    } catch (e) {
      if (i === limitedTryList.length - 1) {
        throw e;
      }
      logger.warn({ err: e, channel: combo.channel, phone: combo.phone }, 'aurax_create_error_retry');
    }
  }
  return lastFailResult;
}

export async function fetchAuraxOrderStatus(orderId: string): Promise<{
  ok: boolean;
  paymentStatus: string;
  raw: Record<string, unknown>;
}> {
  ensureAuraxConfigured();
  const { response, data } = await auraxFetchJson(`/payments/${encodeURIComponent(orderId)}`, {
    method: 'GET',
    headers: auraxHeaders(),
  });
  const tx = (data.transaction ?? data.data ?? data) as Record<string, unknown>;
  const ps = String(
    (tx && typeof tx === 'object' ? tx.status ?? tx.paymentStatus ?? tx.payment_status : '') ??
      data.status ??
      '',
  )
    .toUpperCase()
    .trim();
  return { ok: response.ok, paymentStatus: ps, raw: data };
}

export function isAuraxPaymentCompleted(rawUpper: string): boolean {
  return AURAX_PAID.has(String(rawUpper || '').toUpperCase().trim());
}

export function extractAuraxWebhookPaid(payload: Record<string, unknown>): {
  orderId: string;
  allRefs: string[];
  paid: boolean;
} {
  const tx = (payload.transaction ?? payload.data ?? {}) as Record<string, unknown>;
  const meta = (payload.metadata ?? tx.metadata ?? {}) as Record<string, unknown>;
  const refs = [
    payload.id,
    payload.reference,
    tx.id,
    tx.reference,
    meta.orderId,
    meta.order_id,
  ]
    .map((v) => String(v ?? '').trim())
    .filter(Boolean);
  const status = String(
    payload.status ?? tx.status ?? payload.event ?? payload.type ?? '',
  )
    .toUpperCase()
    .trim();
  const paid =
    isAuraxPaymentCompleted(status) ||
    /paid|success|completed|charge\.succeeded|invoice\.paid/i.test(status);
  return { orderId: refs[0] ?? '', allRefs: [...new Set(refs)], paid };
}

export function verifyAuraxWebhookHmac(rawBody: string, signatureHeader?: string): boolean {
  const secret = env.auraxPayWebhookSecret.trim();
  if (!secret || !signatureHeader) return false;
  const digest = createHmac('sha256', secret).update(rawBody).digest();
  const supplied = String(signatureHeader).trim().replace(/^sha256=/i, '');
  const candidates = [digest.toString('hex'), digest.toString('base64')];
  return candidates.some((candidate) => {
    try {
      const a = Buffer.from(candidate);
      const b = Buffer.from(supplied);
      return a.length === b.length && timingSafeEqual(a, b);
    } catch {
      return false;
    }
  });
}
