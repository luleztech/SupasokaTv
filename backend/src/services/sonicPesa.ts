import { createHmac, timingSafeEqual } from 'crypto';
import { env } from '../config/env';
import { HttpError } from '../middleware/errorHandler';
import { logger } from '../lib/logger';
import {
  isMobileMoneyStkSendFailure,
  isPaymentCreateRetryable,
  isPaymentRateLimitError,
  paymentRateLimitUserMessage,
} from '../lib/paymentProviderErrors';
import {
  detectTzMobileNetwork,
  formatPhoneToIntl255,
  isAirtelLocalPhone,
  isHalotelLocalPhone,
  isSupportedSonicPushWallet,
  isTigoYasLocalPhone,
  isVodacomMpesaLocalPhone,
  phoneCandidatesForSonicPesaApi,
  sonicChannelHintsForNetwork,
  toLocal0Digits,
  walletLabelForLocalPhone,
} from '../lib/tzPhone';

const SONIC_API_BASE = 'https://api.sonicpesa.com/api/v1';
/** Docs: Push USSD via create_order — gateway auto-detects wallet from MSISDN. */
const SONIC_CREATE_ORDER_TIMEOUT_MS = 28_000;
const SONIC_USSD_BUSY_DELAY_MS = 3_000;

const sonicDelay = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

const SONIC_PAID_STATUSES = new Set([
  'SUCCESS',
  'COMPLETED',
  'PAID',
  'COMPLETE',
  'SUCCEEDED',
  'APPROVED',
  'CONFIRMED',
  'SETTLED',
  'SUCCESSFUL',
]);

export function getSonicPesaRequestHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'X-API-KEY': env.sonicPesaApiKey,
    Accept: 'application/json',
  };
  const secret = env.sonicPesaSecretKey.trim();
  if (secret) {
    // Sonic dashboard / error text vary: accept both header names.
    headers['X-SECRET-KEY'] = secret;
    headers['X-API-SECRET'] = secret;
  }
  return headers;
}

export function ensureSonicPesaConfigured(): void {
  if (!env.sonicPesaApiKey.trim()) {
    throw new HttpError(
      500,
      'SONICPESA_API_KEY is not configured on the server',
      'SONIC_KEY_MISSING',
    );
  }
}

async function gatewayFetchJson(
  url: string,
  init: RequestInit,
  timeoutMs = SONIC_CREATE_ORDER_TIMEOUT_MS,
): Promise<{ response: Response; data: Record<string, unknown> }> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...init, signal: ctrl.signal });
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

export function extractSonicResponseMessage(data: Record<string, unknown>): string {
  const nest = data.data;
  const row =
    nest && typeof nest === 'object' && !Array.isArray(nest)
      ? (nest as Record<string, unknown>)
      : Array.isArray(nest) && nest.length > 0 && typeof nest[0] === 'object'
        ? (nest[0] as Record<string, unknown>)
        : null;
  for (const v of [
    data.message,
    data.error,
    data.detail,
    row?.message,
    row?.error,
  ]) {
    const s = String(v ?? '').trim();
    if (s) return s;
  }
  return '';
}

export function extractSonicResponseCode(data: Record<string, unknown>): string {
  const nest = data.data;
  const row =
    nest && typeof nest === 'object' && !Array.isArray(nest)
      ? (nest as Record<string, unknown>)
      : null;
  return String(
    data.resultcode ??
      data.result_code ??
      data.code ??
      row?.resultcode ??
      row?.result_code ??
      row?.code ??
      '',
  ).trim();
}

export function isSonicPushUssdSentMessage(message: string): boolean {
  const m = String(message ?? '').toLowerCase();
  return (
    /push ussd sent|ussd sent|sent to your phone|payment order created successfully/i.test(m) ||
    /you will receive a prompt|prompt sent|waiting for customer/i.test(m)
  );
}

export function isSonicInitiateSuccess(
  sonicData: Record<string, unknown> | null | undefined,
  httpResponse: Response,
): boolean {
  if (!sonicData || typeof sonicData !== 'object') return false;
  const responseMessage = extractSonicResponseMessage(sonicData);
  const responseCode = extractSonicResponseCode(sonicData);
  const orderId = extractSonicOrderId(sonicData);
  const st = String(sonicData.status ?? '')
    .toLowerCase()
    .trim();

  if (orderId && isSonicPushUssdSentMessage(responseMessage)) return true;

  // Explicit gateway failure — do not treat as started.
  if (st === 'error' || st === 'failed') return false;

  // EaMax-compatible: status success / success:true + order_id means Push was accepted.
  // Do not reject solely on nested result codes (9009 etc.) when Sonic already minted an order —
  // that pattern was blocking Vodacom 079 after a real create.
  if (st === 'success' && orderId) return true;
  if (sonicData.success === true && orderId) return true;

  if (isSonicStkSendFailure(responseMessage, responseCode) && !isSonicPushUssdSentMessage(responseMessage)) {
    return false;
  }

  if (orderId && httpResponse.ok && isSonicPushUssdSentMessage(responseMessage)) return true;
  if (orderId && httpResponse.ok && st !== 'error' && st !== 'failed') return true;
  return false;
}

export function extractSonicOrderId(sonicData: Record<string, unknown>): string {
  const nest = sonicData.data;
  const row =
    nest && typeof nest === 'object' && !Array.isArray(nest)
      ? (nest as Record<string, unknown>)
      : Array.isArray(nest) && nest.length > 0 && typeof nest[0] === 'object'
        ? (nest[0] as Record<string, unknown>)
        : sonicData;
  return String(row.order_id ?? row.orderId ?? sonicData.order_id ?? sonicData.orderId ?? '').trim();
}

export function extractSonicPaymentStatus(statusData: Record<string, unknown>): string {
  const d = statusData.data;
  const nest = Array.isArray(d) ? d[0] : d && typeof d === 'object' ? d : null;
  const nestObj = nest && typeof nest === 'object' ? (nest as Record<string, unknown>) : null;
  const candidates = [
    nestObj?.payment_status,
    nestObj?.paymentStatus,
    nestObj?.transaction_status,
    nestObj?.transactionStatus,
    nestObj?.order_status,
    nestObj?.orderStatus,
    nestObj?.status,
    statusData.payment_status,
    statusData.paymentStatus,
    statusData.transaction_status,
    statusData.transactionStatus,
    statusData.status,
  ];
  for (const c of candidates) {
    if (c != null && typeof c !== 'object') {
      const s = String(c).toUpperCase().trim();
      if (s) return s;
    }
  }
  return '';
}

export function isSonicPaymentCompleted(rawUpper: string): boolean {
  if (!rawUpper) return false;
  const u = String(rawUpper).toUpperCase().trim();
  if (SONIC_PAID_STATUSES.has(u)) return true;
  const lower = u.toLowerCase();
  return lower === 'successful' || lower === 'ok' || lower === 'true' || lower === '1';
}

/** True when Sonic status API / webhook body indicates paid even if status string is non-standard. */
export function isSonicRawPaymentCompleted(data: Record<string, unknown>): boolean {
  const ps = extractSonicPaymentStatus(data);
  if (isSonicPaymentCompleted(ps)) return true;
  if (data.success === true) return true;
  const rc = String(data.resultcode ?? data.result_code ?? data.code ?? '').trim();
  if (rc === '000' || rc === '0') {
    const st = String(data.status ?? '').toLowerCase().trim();
    if (st === 'success' || st === 'ok' || st === 'completed' || st === 'paid') return true;
  }
  const nest = data.data;
  if (nest && typeof nest === 'object') {
    const row = Array.isArray(nest) && nest.length > 0 && typeof nest[0] === 'object'
      ? (nest[0] as Record<string, unknown>)
      : (nest as Record<string, unknown>);
    if (row.success === true) return true;
    const nestedPs = extractSonicPaymentStatus({ data: row, status: row.status, payment_status: row.payment_status });
    if (isSonicPaymentCompleted(nestedPs)) return true;
  }
  return false;
}

/**
 * SonicPesa requires the international 255XXXXXXXXX MSISDN for every supported
 * Tanzanian wallet. Keeping one canonical format prevents 061 HaloPesa and 079
 * M-Pesa requests from being mis-routed or retried as a second charge attempt.
 */
export function sonicBuyerPhonesForApi(localPhone: string): string[] {
  return phoneCandidatesForSonicPesaApi(localPhone);
}

/** Canonical SonicPesa API MSISDN: 255XXXXXXXXX. */
export function formatPhoneForSonicPesaApi(local0: string): string {
  return formatPhoneToIntl255(local0);
}

export function sonicPhoneCandidatesForApi(local0: string): string[] {
  return phoneCandidatesForSonicPesaApi(local0);
}

type SonicCreateStep = {
  endpoint: 'payment/create_order' | 'payment/create_order_simple';
  buyer_phone: string;
  timeoutMs: number;
  label: string;
  channel?: string;
};

/**
 * SonicPesa create strategy (SonicPesa-only — no alternate gateway):
 * - Halopesa / Tigo-Yas / Airtel: local `0…` first, then `255…`.
 * - Vodacom: `255…` first, then local.
 * Then channel hints and create_order_simple as fallbacks.
 */
function buildSonicCreateSteps(localPhone: string): SonicCreateStep[] {
  const local0 = toLocal0Digits(localPhone);
  const network = detectTzMobileNetwork(local0);
  const phones = phoneCandidatesForSonicPesaApi(local0);
  const channels = sonicChannelHintsForNetwork(local0);
  const steps: SonicCreateStep[] = [];
  const seen = new Set<string>();

  const addStep = (step: SonicCreateStep) => {
    const key = `${step.endpoint}|${step.buyer_phone}|${step.channel ?? ''}`;
    if (!seen.has(key)) {
      seen.add(key);
      steps.push(step);
    }
  };

  // Auto-detect wallet from MSISDN (preferred phone formats first).
  for (const phone of phones) {
    addStep({
      endpoint: 'payment/create_order',
      buyer_phone: phone,
      timeoutMs: SONIC_CREATE_ORDER_TIMEOUT_MS,
      label: `${phone.startsWith('255') ? 'intl' : 'local'}/${network}/auto`,
    });
  }

  const isNonVodacomWallet =
    isHalotelLocalPhone(local0) || isTigoYasLocalPhone(local0) || isAirtelLocalPhone(local0);

  // Channel hints — try top aliases when auto-detect from MSISDN fails.
  if (phones[0]) {
    for (const channel of channels.slice(0, 3)) {
      addStep({
        endpoint: 'payment/create_order',
        buyer_phone: phones[0],
        timeoutMs: SONIC_CREATE_ORDER_TIMEOUT_MS,
        label: `channel/${network}/${channel}`,
        channel,
      });
    }
  }

  if (isNonVodacomWallet && phones[0]) {
    addStep({
      endpoint: 'payment/create_order_simple',
      buyer_phone: phones[0],
      timeoutMs: SONIC_CREATE_ORDER_TIMEOUT_MS,
      label: `simple/${network}/${phones[0].startsWith('255') ? 'intl' : 'local'}`,
    });
  }

  if (steps.length === 0) {
    steps.push(buildSonicPrimaryCreateStep(local0));
  }
  return steps;
}

/** Test hook — mirrors production step builder without hitting SonicPesa API. */
export function buildSonicCreateStepsForTest(localPhone: string): SonicCreateStep[] {
  return buildSonicCreateSteps(localPhone);
}

function buildSonicPrimaryCreateStep(localPhone: string): SonicCreateStep {
  const local0 = toLocal0Digits(localPhone);
  const network = detectTzMobileNetwork(local0);
  return {
    endpoint: 'payment/create_order',
    buyer_phone: formatPhoneToIntl255(local0),
    timeoutMs: SONIC_CREATE_ORDER_TIMEOUT_MS,
    label: `intl/${network}/auto`,
  };
}

function isSonicUssdBusy(responseMessage: string, responseCode: string): boolean {
  const code = String(responseCode ?? '').trim();
  const msg = String(responseMessage ?? '').toLowerCase();
  return code === '103' || /ongoing ussd|ussd session|session busy/i.test(msg);
}

async function postSonicCreateOrder(
  step: SonicCreateStep,
  args: {
    buyerEmail: string;
    buyerName: string;
    amountTzs: number;
    publicId?: string;
    planId?: string;
  },
): Promise<{ response: Response; data: Record<string, unknown> }> {
  const publicId = String(args.publicId ?? '').trim();
  const planId = String(args.planId ?? '').trim();
  const amount = Math.max(1, Math.trunc(Number(args.amountTzs) || 0));
  const payload: Record<string, unknown> = {
    buyer_email: args.buyerEmail,
    buyer_name: args.buyerName,
    buyer_phone: step.buyer_phone,
    amount,
    currency: 'TZS',
  };
  if (step.channel) {
    // Only set Sonic's documented channel field — do not also stamp provider/network/operator
    // with the same string (some gateways reject unknown operator enums and block Halopesa/Airtel).
    payload.channel = step.channel;
  }
  // Attach identity so webhooks can recover premium even if local intent insert raced.
  if (publicId || planId) {
    payload.metadata = {
      ...(publicId ? { external_id: publicId, public_id: publicId } : {}),
      ...(planId ? { plan_id: planId } : {}),
    };
  }
  return gatewayFetchJson(
    `${SONIC_API_BASE}/${step.endpoint}`,
    {
      method: 'POST',
      headers: getSonicPesaRequestHeaders(),
      body: JSON.stringify(payload),
    },
    step.timeoutMs,
  );
}


export function isSonicStkSendFailure(rawMessage: string, rawCode: string): boolean {
  return isMobileMoneyStkSendFailure(rawMessage, rawCode);
}

/** Swahili user-facing message for SonicPesa checkout failures — all TZ networks. */
export function mapSonicInitiateUserError(
  localPhone: string,
  rawMessage: string,
  rawCode: string,
): string {
  const code = String(rawCode ?? '').trim();
  const msg = String(rawMessage || '').trim();
  const hayajatumika = /hayajatumika|hayajaweza kutumika|hayajaweza kutuma/i.test(msg);
  const wallet = walletLabelForLocalPhone(localPhone);
  if (code === '103' || /ongoing ussd/i.test(msg)) {
    return 'Simu yako ina USSD nyingine zinazoendelea. Funga dirisha la malipo/USSD kwenye simu, subiri sekunde 30, kisha jaribu tena.';
  }
  if (isPaymentRateLimitError(msg, code)) {
    return paymentRateLimitUserMessage();
  }
  if (isSonicStkSendFailure(msg, code) || hayajatumika) {
    if (isHalotelLocalPhone(localPhone)) {
      return 'Halopesa (061–063) haikupokea ombi. Hakikisha nambari ni sahihi, una salio, na mtandao wa Halopesa unafanya kazi, kisha jaribu tena.';
    }
    const network = detectTzMobileNetwork(toLocal0Digits(localPhone));
    if (network === 'airtel') {
      return 'Hatukuweza kutuma ombi la Airtel Money kwenye simu yako. Hakikisha nambari ni sahihi (066/068/069/078), una salio, na Airtel Money inafanya kazi, kisha jaribu tena.';
    }
    if (network === 'tigo_yas') {
      return 'Hatukuweza kutuma ombi la TigoPesa/Mixx (Yas) kwenye simu yako. Hakikisha nambari ni sahihi (065/067/070/071/077), una salio, na TigoPesa inafanya kazi, kisha jaribu tena.';
    }
    if (network === 'vodacom' || isVodacomMpesaLocalPhone(localPhone)) {
      return 'Hatukuweza kutuma ombi la M-Pesa (Vodacom) kwenye simu yako. Hakikisha nambari 074, 075, 076 au 079 ni sahihi, una salio, na M-Pesa inafanya kazi, kisha jaribu tena.';
    }
    if (network === 'ttcl' || network === 'smile' || network === 'cootel') {
      return `Nambari hii inaonekana kama ${wallet}. Tumia nambari ya M-Pesa, TigoPesa/Yas, Airtel Money au Halopesa ili kupokea Push USSD.`;
    }
    return `Hatukuweza kutuma ombi la ${wallet} kwenye simu yako. Hakikisha nambari ni sahihi, una salio, na mtandao wa pesa unafanya kazi, kisha jaribu tena.`;
  }
  if (
    /invalid phone|invalid msisdn|wrong number|invalid.*msisdn|nambari.*si sahihi|si sahihi.*nambari/i.test(
      `${msg} ${code}`,
    )
  ) {
    return 'Hatukuweza kutuma ombi kwa nambari hii. Hakikisha unaandika nambari yako kamili ya simu ukianza na 0 (mfano 0712345678), una M-Pesa/Tigo/Airtel/Halopesa, na jaribu tena.';
  }
  if (!isSupportedSonicPushWallet(localPhone)) {
    return `Nambari hii (${wallet}) huenda isitumie Push USSD. Tumia M-Pesa (074–079), Tigo/Yas (065/067/070/071/077), Airtel (066/068/069/078) au Halopesa (061–063).`;
  }
  return msg || 'Malipo hayajatumika. Jaribu tena baada ya muda mfupi.';
}

export type SonicCreateResult = {
  ok: boolean;
  orderId: string;
  message: string;
  raw: Record<string, unknown>;
  errorMessage?: string;
  errorCode?: string;
};

export async function tryCreateSonicOrder(args: {
  buyerEmail: string;
  buyerName: string;
  localPhone: string;
  amountTzs: number;
  publicId?: string;
  planId?: string;
}): Promise<SonicCreateResult> {
  ensureSonicPesaConfigured();
  const local0 = toLocal0Digits(args.localPhone);
  const network = detectTzMobileNetwork(local0);
  const amountTzs = Math.max(1, Math.trunc(Number(args.amountTzs) || 0));
  const steps: SonicCreateStep[] = buildSonicCreateSteps(local0);
  let last: { response: Response; data: Record<string, unknown> } = {
    response: new Response(null, { status: 500 }),
    data: { status: 'error', message: 'Failed to start SonicPesa payment' },
  };

  logger.info(
    { network, wallet: walletLabelForLocalPhone(local0), steps: steps.map((s) => s.label) },
    'sonic_create_begin',
  );

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]!;
    try {
      last = await postSonicCreateOrder(step, { ...args, amountTzs });
      const responseMessage = extractSonicResponseMessage(last.data);
      const responseCode = extractSonicResponseCode(last.data);

      // Same-step retry only when handset already has an open USSD session.
      if (isSonicUssdBusy(responseMessage, responseCode)) {
        await sonicDelay(SONIC_USSD_BUSY_DELAY_MS);
        last = await postSonicCreateOrder(step, { ...args, amountTzs });
      }

      const retryMessage = extractSonicResponseMessage(last.data);
      const retryCode = extractSonicResponseCode(last.data);

      if (isSonicInitiateSuccess(last.data, last.response)) {
        const orderId = extractSonicOrderId(last.data);
        // Trust gateway success + order id (same as EaMax). Push-sent wording is ideal
        // but not required — rejecting here left Vodacom 079 stuck after a valid create.
        if (orderId) {
          logger.info(
            { orderId, network, step: step.label, phone: step.buyer_phone },
            'sonic_create_ok',
          );
          return {
            ok: true,
            orderId,
            message: String(
              last.data.message ??
                'Payment order created successfully! Push USSD sent to your phone.',
            ),
            raw: last.data,
          };
        }
      }

      const errorMessage = retryMessage || 'Failed to start SonicPesa payment';
      const errorCode = retryCode;
      logger.warn(
        { network, step: step.label, errorMessage, errorCode, phone: step.buyer_phone },
        'sonic_create_step_failed',
      );
      if (isPaymentRateLimitError(errorMessage, errorCode)) {
        return {
          ok: false,
          orderId: '',
          message: paymentRateLimitUserMessage(),
          raw: last.data,
          errorMessage: paymentRateLimitUserMessage(),
          errorCode,
        };
      }
      // STK not delivered — try next phone format / channel step.
      if (isSonicStkSendFailure(errorMessage, errorCode)) {
        break;
      }
      // Invalid MSISDN / unknown channel — try next format or primary channel hint.
      if (i < steps.length - 1 && isPaymentCreateRetryable(errorMessage, errorCode)) {
        continue;
      }
      // Soft/unknown gateway error: allow one more alternate step, then stop.
      if (i < steps.length - 1 && i === 0) {
        continue;
      }
      break;
    } catch (e) {
      last = {
        response: new Response(null, { status: 502 }),
        data: { status: 'error', message: e instanceof Error ? e.message : String(e) },
      };
      const msg = e instanceof Error ? e.message : String(e);
      logger.warn({ network, step: step.label, err: msg }, 'sonic_create_step_exception');
      // Transport blip — try next step.
      if (i < steps.length - 1) {
        continue;
      }
      break;
    }
  }

  const errorMessage = extractSonicResponseMessage(last.data) || 'Failed to start SonicPesa payment';
  const errorCode = extractSonicResponseCode(last.data);
  if (isPaymentRateLimitError(errorMessage, errorCode)) {
    return {
      ok: false,
      orderId: '',
      message: paymentRateLimitUserMessage(),
      raw: last.data,
      errorMessage: paymentRateLimitUserMessage(),
      errorCode,
    };
  }
  logger.warn({ network, errorMessage, errorCode }, 'sonic_create_failed');
  return {
    ok: false,
    orderId: '',
    message: errorMessage,
    raw: last.data,
    errorMessage: mapSonicInitiateUserError(args.localPhone, errorMessage, errorCode),
    errorCode,
  };
}

export async function createSonicOrder(args: {
  buyerEmail: string;
  buyerName: string;
  localPhone: string;
  amountTzs: number;
}): Promise<{
  orderId: string;
  message: string;
  raw: Record<string, unknown>;
}> {
  const out = await tryCreateSonicOrder(args);
  if (!out.ok) {
    throw new HttpError(400, out.errorMessage ?? 'Failed to start SonicPesa payment', 'SONIC_CREATE_FAILED');
  }
  return { orderId: out.orderId, message: out.message, raw: out.raw };
}

export async function fetchSonicOrderStatus(orderId: string): Promise<{
  ok: boolean;
  paymentStatus: string;
  raw: Record<string, unknown>;
}> {
  ensureSonicPesaConfigured();
  const { response, data } = await gatewayFetchJson(`${SONIC_API_BASE}/payment/order_status`, {
    method: 'POST',
    headers: getSonicPesaRequestHeaders(),
    body: JSON.stringify({ order_id: orderId }),
  });
  const ps = extractSonicPaymentStatus(data);
  return { ok: response.ok, paymentStatus: ps, raw: data };
}

function timingSafeEqualHexOrString(a: string, b: string): boolean {
  const x = a.trim().toLowerCase();
  const y = b.trim().toLowerCase();
  const xa = x.includes('=') ? (x.split('=').pop()?.trim() ?? x) : x;
  const yb = y.includes('=') ? (y.split('=').pop()?.trim() ?? y) : y;
  if (xa.length !== yb.length) return false;
  try {
    const bx = Buffer.from(xa, 'hex');
    const by = Buffer.from(yb, 'hex');
    if (bx.length > 0 && bx.length === by.length && bx.length === xa.length / 2) {
      return timingSafeEqual(bx, by);
    }
  } catch {
    /* fall through */
  }
  const bufA = Buffer.from(xa, 'utf8');
  const bufB = Buffer.from(yb, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

export function verifySonicPesaWebhookHmac(rawBodyString: string, headerValue: string | undefined): boolean {
  const secret = env.sonicPesaWebhookSecret.trim();
  if (!secret || typeof headerValue !== 'string' || !headerValue.trim()) return false;
  if (!rawBodyString.length) return false;
  const expected = createHmac('sha256', secret).update(rawBodyString, 'utf8').digest('hex');
  return (
    timingSafeEqualHexOrString(headerValue, expected) ||
    timingSafeEqualHexOrString(headerValue, `sha256=${expected}`)
  );
}

export function extractSonicWebhookPaid(payload: Record<string, unknown>): {
  orderId: string | null;
  paid: boolean;
} {
  const d = payload.data;
  const nest =
    d && typeof d === 'object' && !Array.isArray(d)
      ? (d as Record<string, unknown>)
      : Array.isArray(d) && d.length > 0 && typeof d[0] === 'object'
        ? (d[0] as Record<string, unknown>)
        : null;
  const orderId = String(
    payload.order_id ??
      payload.orderId ??
      nest?.order_id ??
      nest?.orderId ??
      payload.reference ??
      payload.reference_id ??
      payload.invoice_id ??
      nest?.reference ??
      '',
  ).trim();

  const st = String(nest?.status ?? nest?.payment_status ?? nest?.paymentStatus ?? payload.status ?? '')
    .toUpperCase()
    .trim();
  const ev = String(payload.event ?? payload.type ?? '')
    .toLowerCase()
    .trim();
  let paid = SONIC_PAID_STATUSES.has(st) || isSonicRawPaymentCompleted(payload);
  if (!paid && ev) {
    paid =
      ev === 'payment.success' ||
      ev === 'payment.completed' ||
      ev === 'payment_completed' ||
      ev === 'payment.paid' ||
      ev === 'order.paid' ||
      ev === 'order.completed' ||
      ev === 'invoice.paid' ||
      ev === 'charge.succeeded' ||
      ev === 'transaction.success' ||
      ev.endsWith('.success') ||
      ev.endsWith('.completed') ||
      ev.endsWith('.paid');
  }
  if (!paid) {
    const rc = String(
      payload.resultcode ?? payload.result_code ?? nest?.resultcode ?? nest?.result_code ?? '',
    ).trim();
    const msg = String(payload.message ?? nest?.message ?? '').toLowerCase();
    if ((rc === '000' || rc === '0') && (msg.includes('success') || msg.includes('paid') || msg.includes('complete'))) {
      paid = true;
    }
  }
  return { orderId: orderId || null, paid };
}
