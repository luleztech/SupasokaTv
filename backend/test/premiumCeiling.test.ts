import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { hasRecordedGrant, paidPremiumCeilingMs } from '../src/services/premiumCeiling.ts';

const DAY = 24 * 60 * 60 * 1000;
const T0 = 1_800_000_000_000;

describe('paid premium ceiling', () => {
  it('trusts the window recorded at activation, whatever the plan table says now', () => {
    const ceiling = paidPremiumCeilingMs([
      { activatedAtMs: T0, grantedUntilMs: T0 + 30 * DAY, fallbackDurationMs: 1 * DAY },
    ]);
    assert.equal(ceiling, T0 + 30 * DAY);
  });

  it('uses the plan length only for legacy orders without a recorded grant', () => {
    const ceiling = paidPremiumCeilingMs([
      { activatedAtMs: T0, grantedUntilMs: null, fallbackDurationMs: 7 * DAY },
    ]);
    assert.equal(ceiling, T0 + 7 * DAY);
  });

  it('treats a stamp that is not after activation as no recorded grant', () => {
    assert.equal(hasRecordedGrant({ activatedAtMs: T0, grantedUntilMs: T0, fallbackDurationMs: DAY }), false);
    assert.equal(hasRecordedGrant({ activatedAtMs: T0, grantedUntilMs: T0 - 5, fallbackDurationMs: DAY }), false);
    assert.equal(hasRecordedGrant({ activatedAtMs: T0, grantedUntilMs: T0 + 1, fallbackDurationMs: DAY }), true);
  });

  it('keeps stacked renewals: a second order extends the first', () => {
    const ceiling = paidPremiumCeilingMs([
      { activatedAtMs: T0 + 5 * DAY, grantedUntilMs: T0 + 37 * DAY, fallbackDurationMs: 30 * DAY },
      { activatedAtMs: T0, grantedUntilMs: T0 + 30 * DAY, fallbackDurationMs: 30 * DAY },
    ]);
    assert.equal(ceiling, T0 + 37 * DAY);
  });

  it('stacks consecutive legacy orders oldest first', () => {
    const ceiling = paidPremiumCeilingMs([
      { activatedAtMs: T0 + DAY, grantedUntilMs: null, fallbackDurationMs: 7 * DAY },
      { activatedAtMs: T0, grantedUntilMs: null, fallbackDurationMs: 7 * DAY },
    ]);
    assert.equal(ceiling, T0 + 14 * DAY);
  });

  it('is zero when there is no paid order', () => {
    assert.equal(paidPremiumCeilingMs([]), 0);
  });
});
