/**
 * Sanity: Vodacom/Airtel stay on one intl-255 auto create.
 * HaloPesa and Yas/Tigo use national 0… plus the wallet channel so Sonic sends the push.
 * Run: npx tsx scripts/verify-sonic-create-steps.ts
 */
import {
  isPaymentApiThrottleError,
  isPaymentRateLimitError,
  paymentBusyUserMessage,
  paymentRateLimitUserMessage,
} from '../src/lib/paymentProviderErrors';
import { phoneCandidatesForSonicPesaApi, sonicDispatchChannel } from '../src/lib/tzPhone';
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
  const auto: Array<{ phone: string; network: string }> = [
    { phone: '0752345678', network: 'vodacom' },
    { phone: '0792345678', network: 'vodacom' },
    { phone: '0682345678', network: 'airtel' },
    { phone: '0782345678', network: 'airtel' },
  ];
  const routed: Array<{ phone: string; network: string; channel: string }> = [
    { phone: '0612345678', network: 'halotel', channel: 'HALOPESA' },
    { phone: '0622345678', network: 'halotel', channel: 'HALOPESA' },
    { phone: '0632345678', network: 'halotel', channel: 'HALOPESA' },
    { phone: '0652345678', network: 'tigo_yas', channel: 'TIGOPESATZ' },
    { phone: '0672345678', network: 'tigo_yas', channel: 'TIGOPESATZ' },
    { phone: '0702345678', network: 'tigo_yas', channel: 'TIGOPESATZ' },
    { phone: '0712345678', network: 'tigo_yas', channel: 'TIGOPESATZ' },
    { phone: '0772345678', network: 'tigo_yas', channel: 'TIGOPESATZ' },
  ];

  for (const { phone, network } of auto) {
    const steps = buildSonicCreateStepsForTest(phone);
    assert(steps.length === 1, `${network} expected 1 Sonic step, got ${steps.length}`);
    assert(
      steps[0]!.buyer_phone.startsWith('255') && steps[0]!.buyer_phone.length === 12,
      `${network} must use intl 255XXXXXXXXX, got ${steps[0]!.buyer_phone}`,
    );
    assert(!steps[0]!.channel, `${network} must not force channel (auto-detect)`);
    const phones = phoneCandidatesForSonicPesaApi(phone);
    assert(phones.length === 1 && phones[0] === steps[0]!.buyer_phone, `${network} candidate mismatch`);
    assert(sonicDispatchChannel(phone) === undefined, `${network} must stay auto-detect`);
  }

  for (const { phone, network, channel } of routed) {
    const steps = buildSonicCreateStepsForTest(phone);
    assert(steps.length === 2, `${phone} expected local + intl fallback, got ${steps.length}`);
    assert(
      steps[0]!.buyer_phone === phone && steps[0]!.channel === channel,
      `${phone} primary must be national ${phone} + ${channel}, got ${steps[0]!.buyer_phone}/${steps[0]!.channel}`,
    );
    assert(
      steps[1]!.buyer_phone === `255${phone.slice(1)}` && steps[1]!.channel === channel,
      `${phone} fallback must keep ${channel} on 255…`,
    );
    const phones = phoneCandidatesForSonicPesaApi(phone);
    assert(phones.length === 1 && phones[0] === phone, `${network} primary candidate must be national`);
    assert(sonicDispatchChannel(phone) === channel, `${phone} dispatch channel`);
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
      auto: auto.map((s) => ({
        network: s.network,
        buyer: buildSonicCreateStepsForTest(s.phone)[0]!.buyer_phone,
      })),
      routed: routed.map((s) => ({
        network: s.network,
        phone: s.phone,
        buyer: buildSonicCreateStepsForTest(s.phone)[0]!.buyer_phone,
        channel: buildSonicCreateStepsForTest(s.phone)[0]!.channel,
      })),
    }),
  );
}

main();
