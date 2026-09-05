/**
 * Sanity: one intl-255 Sonic create per network; no false "majaribio" on API throttle.
 * Run: npx tsx scripts/verify-sonic-create-steps.ts
 */
import {
  isPaymentApiThrottleError,
  isPaymentRateLimitError,
  paymentBusyUserMessage,
  paymentRateLimitUserMessage,
} from '../src/lib/paymentProviderErrors';
import { phoneCandidatesForSonicPesaApi } from '../src/lib/tzPhone';
import { buildSonicCreateStepsForTest, mapSonicInitiateUserError } from '../src/services/sonicPesa';
import {
  clearPaymentStartCooldown,
  markPaymentStartSent,
  paymentStartCooldownMessage,
} from '../src/services/paymentStartCooldown';

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function main() {
  const samples: Array<{ phone: string; network: string }> = [
    { phone: '0752345678', network: 'vodacom' },
    { phone: '0792345678', network: 'vodacom' },
    { phone: '0712345678', network: 'tigo_yas' },
    { phone: '0702345678', network: 'tigo_yas' },
    { phone: '0682345678', network: 'airtel' },
    { phone: '0622345678', network: 'halotel' },
  ];

  for (const { phone, network } of samples) {
    const steps = buildSonicCreateStepsForTest(phone);
    assert(steps.length === 1, `${network} expected 1 Sonic step, got ${steps.length}`);
    assert(
      steps[0]!.buyer_phone.startsWith('255') && steps[0]!.buyer_phone.length === 12,
      `${network} must use intl 255XXXXXXXXX, got ${steps[0]!.buyer_phone}`,
    );
    assert(!steps[0]!.channel, `${network} must not force channel (auto-detect)`);
    const phones = phoneCandidatesForSonicPesaApi(phone);
    assert(phones.length === 1, `${network} phone candidates must be single intl`);
    assert(phones[0] === steps[0]!.buyer_phone, `${network} candidate mismatch`);
  }

  assert(
    !isPaymentRateLimitError('Too Many Attempts.', ''),
    'bare Too Many Attempts must NOT be per-number quota',
  );
  assert(
    isPaymentApiThrottleError('Too Many Attempts.', ''),
    'bare Too Many Attempts must be API throttle',
  );
  assert(
    isPaymentRateLimitError('Too many attempts for this number', ''),
    'phone-tied attempts remain per-number',
  );
  assert(
    mapSonicInitiateUserError('0712345678', 'Too Many Attempts.', '') === paymentBusyUserMessage(),
    'map bare throttle → busy message',
  );
  assert(
    mapSonicInitiateUserError('0712345678', 'Too many attempts for this phone', '') ===
      paymentRateLimitUserMessage(),
    'map phone quota → majaribio message',
  );

  assert(paymentStartCooldownMessage('0712345678') === null, 'no cooldown before success');
  markPaymentStartSent('0712345678', 'order-test-1');
  assert(
    paymentStartCooldownMessage('0712345678') != null,
    'cooldown after successful STK dispatch',
  );
  clearPaymentStartCooldown('0712345678');
  assert(paymentStartCooldownMessage('0712345678') === null, 'cooldown clears on reset');

  console.log(
    JSON.stringify({
      ok: true,
      networks: samples.map((s) => ({
        network: s.network,
        phone: s.phone,
        buyer: buildSonicCreateStepsForTest(s.phone)[0]!.buyer_phone,
      })),
    }),
  );
}

main();
