/**
 * Checkout dispatch under a burst of payers.
 *
 * PIN prompts are sent by SonicPesa / Aurax. Firing every "Lipia sasa" at the
 * gateway at once makes the gateway time out, and the handset never shows a PIN.
 * Creates run through a small FIFO lane. Extra payers wait their turn instead of
 * all failing together. Status checks use a separate lane and a short cache so
 * polling cannot take the slots needed to send PINs.
 */

function readPositiveInt(name: string, fallback: number, min: number, max: number): number {
  const n = Number.parseInt(process.env[name] ?? '', 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

const CREATE_LIMIT = readPositiveInt('PAYMENT_CREATE_CONCURRENCY', 6, 2, 12);
const CREATE_WAIT_MS = readPositiveInt('PAYMENT_CREATE_QUEUE_WAIT_MS', 70_000, 5_000, 90_000);
const STATUS_LIMIT = readPositiveInt('PAYMENT_STATUS_CONCURRENCY', 8, 2, 24);
const STATUS_WAIT_MS = readPositiveInt('PAYMENT_STATUS_QUEUE_WAIT_MS', 8_000, 500, 20_000);

function laneLog(level: 'info' | 'warn', fields: Record<string, unknown>, msg: string): void {
  const line = JSON.stringify({ level, msg, ...fields });
  if (level === 'warn') console.warn(line);
  else console.info(line);
}

export class PaymentDispatchBusyError extends Error {
  readonly code = 'PAYMENT_BUSY' as const;

  constructor(message?: string) {
    super(
      message ??
        'Watu wengi wanalipa kwa wakati mmoja. Subiri sekunde chache, kisha gusa Lipia sasa mara moja. Usibonyeze mara nyingi.',
    );
    this.name = 'PaymentDispatchBusyError';
  }
}

type Waiter = {
  resolve: (admitted: boolean) => void;
  timer: ReturnType<typeof setTimeout>;
};

export class PaymentLane {
  private active = 0;
  private readonly waiters: Waiter[] = [];
  private readonly limit: number;
  private readonly waitMs: number;

  constructor(limit: number, waitMs: number) {
    this.limit = limit;
    this.waitMs = waitMs;
  }

  get running(): number {
    return this.active;
  }

  get queued(): number {
    return this.waiters.length;
  }

  acquire(): Promise<boolean> {
    if (this.active < this.limit) {
      this.active += 1;
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve) => {
      const waiter: Waiter = {
        resolve,
        timer: setTimeout(() => {
          const index = this.waiters.indexOf(waiter);
          if (index >= 0) this.waiters.splice(index, 1);
          resolve(false);
        }, this.waitMs),
      };
      this.waiters.push(waiter);
    });
  }

  /**
   * Hands the slot to the next waiter without dropping `active` to zero first.
   * Decrementing before the handoff let a new caller sneak in and exceed the limit.
   */
  release(): void {
    const next = this.waiters.shift();
    if (next) {
      clearTimeout(next.timer);
      next.resolve(true);
      return;
    }
    this.active = Math.max(0, this.active - 1);
  }
}

export type DispatchLanes = {
  createLane: PaymentLane;
  statusLane: PaymentLane;
  coalesceCreate: <T>(phoneKey: string, work: () => Promise<T>) => Promise<T>;
  cachedStatus: <T>(key: string, ttlMs: number, work: () => Promise<T>, fallback: T) => Promise<T>;
  snapshot: () => {
    createActive: number;
    createQueued: number;
    statusActive: number;
    statusQueued: number;
    inFlightPhones: number;
  };
};

export function createDispatchLanes(opts?: {
  createLimit?: number;
  createWaitMs?: number;
  statusLimit?: number;
  statusWaitMs?: number;
}): DispatchLanes {
  const createLane = new PaymentLane(opts?.createLimit ?? CREATE_LIMIT, opts?.createWaitMs ?? CREATE_WAIT_MS);
  const statusLane = new PaymentLane(opts?.statusLimit ?? STATUS_LIMIT, opts?.statusWaitMs ?? STATUS_WAIT_MS);
  const inFlight = new Map<string, Promise<unknown>>();
  const statusInFlight = new Map<string, Promise<unknown>>();
  const statusCache = new Map<string, { at: number; value: unknown }>();

  function pruneStatusCache(): void {
    if (statusCache.size < 1500) return;
    const cutoff = Date.now() - 60_000;
    for (const [key, entry] of statusCache) {
      if (entry.at < cutoff) statusCache.delete(key);
    }
  }

  function coalesceCreate<T>(phoneKey: string, work: () => Promise<T>): Promise<T> {
    const key = phoneKey.trim();
    const existing = inFlight.get(key);
    if (existing) return existing as Promise<T>;

    const job = (async () => {
      const queuedBefore = createLane.queued;
      const started = Date.now();
      const admitted = await createLane.acquire();
      const waitMs = Date.now() - started;
      if (!admitted) {
        laneLog('warn', { phone: key, queuedBefore, waitMs }, 'payment_create_queue_timeout');
        throw new PaymentDispatchBusyError();
      }
      if (waitMs >= 250) {
        laneLog(
          'info',
          { phone: key, waitMs, queuedBefore, active: createLane.running },
          'payment_create_lane_acquired',
        );
      }
      try {
        return await work();
      } finally {
        createLane.release();
      }
    })();

    inFlight.set(key, job);
    void job.then(
      () => {
        if (inFlight.get(key) === job) inFlight.delete(key);
      },
      () => {
        if (inFlight.get(key) === job) inFlight.delete(key);
      },
    );
    return job;
  }

  function cachedStatus<T>(key: string, ttlMs: number, work: () => Promise<T>, fallback: T): Promise<T> {
    const now = Date.now();
    const hit = statusCache.get(key);
    if (hit && now - hit.at < ttlMs) return Promise.resolve(hit.value as T);

    const existing = statusInFlight.get(key);
    if (existing) return existing as Promise<T>;

    const job = (async () => {
      const admitted = await statusLane.acquire();
      if (!admitted) {
        const again = statusCache.get(key);
        if (again) return again.value as T;
        return fallback;
      }
      try {
        const freshHit = statusCache.get(key);
        if (freshHit && Date.now() - freshHit.at < ttlMs) return freshHit.value as T;
        const value = await work();
        statusCache.set(key, { at: Date.now(), value });
        pruneStatusCache();
        return value;
      } finally {
        statusLane.release();
      }
    })();

    statusInFlight.set(key, job);
    void job.then(
      () => {
        if (statusInFlight.get(key) === job) statusInFlight.delete(key);
      },
      () => {
        if (statusInFlight.get(key) === job) statusInFlight.delete(key);
      },
    );
    return job;
  }

  return {
    createLane,
    statusLane,
    coalesceCreate,
    cachedStatus,
    snapshot: () => ({
      createActive: createLane.running,
      createQueued: createLane.queued,
      statusActive: statusLane.running,
      statusQueued: statusLane.queued,
      inFlightPhones: inFlight.size,
    }),
  };
}

const lanes = createDispatchLanes();

/** One in-flight PIN dispatch per phone. Other taps wait for that result. */
export function coalescePaymentCreate<T>(phoneKey: string, work: () => Promise<T>): Promise<T> {
  return lanes.coalesceCreate(phoneKey, work);
}

/**
 * Share one provider status read across every poller of the same order.
 * If the status lane is full, return the last value or `fallback` (PENDING)
 * so the app keeps waiting instead of failing the PIN session.
 */
export function fetchPaymentStatusCached<T>(
  key: string,
  ttlMs: number,
  work: () => Promise<T>,
  fallback: T,
): Promise<T> {
  return lanes.cachedStatus(key, ttlMs, work, fallback);
}

export function paymentDispatchSnapshot(): ReturnType<DispatchLanes['snapshot']> {
  return lanes.snapshot();
}

export const PAYMENT_STATUS_CACHE_MS = readPositiveInt('PAYMENT_STATUS_CACHE_MS', 4_000, 1_000, 15_000);
