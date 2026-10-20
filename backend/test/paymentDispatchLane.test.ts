import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  PaymentDispatchBusyError,
  createDispatchLanes,
} from '../src/services/paymentDispatchLane.ts';

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe('payment dispatch lane', () => {
  it('keeps a burst of checkouts inside the concurrency cap and finishes all of them', async () => {
    const lanes = createDispatchLanes({ createLimit: 4, createWaitMs: 5_000 });
    let active = 0;
    let maxActive = 0;
    const jobs = Array.from({ length: 24 }, (_, i) =>
      lanes.coalesceCreate(`255700000${String(i).padStart(3, '0')}`, async () => {
        active += 1;
        maxActive = Math.max(maxActive, active);
        await delay(30);
        active -= 1;
        return i;
      }),
    );
    const results = await Promise.all(jobs);
    assert.equal(results.length, 24);
    assert.deepEqual(results, results.slice().sort((a, b) => a - b));
    assert.ok(maxActive <= 4, `expected at most 4 in flight, saw ${maxActive}`);
    assert.ok(maxActive >= 2, 'lane should actually run work in parallel');
    assert.equal(lanes.snapshot().createActive, 0);
    assert.equal(lanes.snapshot().createQueued, 0);
  });

  it('joins a second tap on the same phone to the in-flight PIN dispatch', async () => {
    const lanes = createDispatchLanes({ createLimit: 2, createWaitMs: 2_000 });
    let calls = 0;
    const first = lanes.coalesceCreate('0712345678', async () => {
      calls += 1;
      await delay(40);
      return 'order-1';
    });
    const second = lanes.coalesceCreate('0712345678', async () => {
      calls += 1;
      return 'order-2';
    });
    assert.equal(await first, 'order-1');
    assert.equal(await second, 'order-1');
    assert.equal(calls, 1);
  });

  it('keeps every payer in line when the queue has no time limit', async () => {
    const lanes = createDispatchLanes({ createLimit: 1, createWaitMs: 0 });
    let release: () => void = () => {};
    const holding = new Promise<void>((resolve) => {
      release = resolve;
    });
    const first = lanes.coalesceCreate('0610000011', () => holding.then(() => 'held'));
    await delay(80);
    const second = lanes.coalesceCreate('0610000012', async () => 'next');
    assert.equal(lanes.snapshot().createQueued, 1);
    release();
    assert.equal(await first, 'held');
    assert.equal(await second, 'next');
    assert.equal(lanes.snapshot().createActive, 0);
    assert.equal(lanes.snapshot().createQueued, 0);
  });

  it('fails fast when the create queue cannot admit another payer in time', async () => {
    const lanes = createDispatchLanes({ createLimit: 1, createWaitMs: 40 });
    let release: () => void = () => {};
    const holding = new Promise<void>((resolve) => {
      release = resolve;
    });
    const first = lanes.coalesceCreate('0610000001', () => holding.then(() => 'held'));
    await delay(5);
    await assert.rejects(
      lanes.coalesceCreate('0610000002', async () => 'should-not-run'),
      (err: unknown) => err instanceof PaymentDispatchBusyError,
    );
    release();
    assert.equal(await first, 'held');
    assert.equal(lanes.snapshot().createActive, 0);
  });

  it('shares one status read across pollers and serves the cache', async () => {
    const lanes = createDispatchLanes({ statusLimit: 2, statusWaitMs: 1_000 });
    let calls = 0;
    const work = async () => {
      calls += 1;
      await delay(20);
      return 'PENDING';
    };
    const [a, b] = await Promise.all([
      lanes.cachedStatus('sonic:ord', 5_000, work, 'FALLBACK'),
      lanes.cachedStatus('sonic:ord', 5_000, work, 'FALLBACK'),
    ]);
    assert.equal(a, 'PENDING');
    assert.equal(b, 'PENDING');
    assert.equal(calls, 1);
    const again = await lanes.cachedStatus('sonic:ord', 5_000, work, 'FALLBACK');
    assert.equal(again, 'PENDING');
    assert.equal(calls, 1);
  });

  it('returns the pending fallback when status checks are saturated', async () => {
    const lanes = createDispatchLanes({ statusLimit: 1, statusWaitMs: 30 });
    let release: () => void = () => {};
    const holding = new Promise<void>((resolve) => {
      release = resolve;
    });
    const first = lanes.cachedStatus('sonic:busy', 10, async () => {
      await holding;
      return 'LIVE';
    }, 'PENDING');
    await delay(5);
    const fallback = await lanes.cachedStatus('sonic:other', 10, async () => 'FRESH', 'PENDING');
    assert.equal(fallback, 'PENDING');
    release();
    assert.equal(await first, 'LIVE');
  });
});
