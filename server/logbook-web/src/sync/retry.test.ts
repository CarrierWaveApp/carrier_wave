// Unit tests for the blob-upload retry policy (CAR-322). Pure module, no DOM.
import { describe, expect, it } from 'vitest';
import {
  RETRY_ATTEMPTS,
  backoffDelayMs,
  classifyStatus,
  isTransientStatus,
  putWithRetry,
} from './retry';

function response(status: number): Response {
  return { status, ok: status >= 200 && status <= 299 } as Response;
}

/** A fetch stub that replays `script` in order; a `'throw'` entry rejects like a network fault. */
function scriptedFetch(script: Array<number | 'throw'>) {
  const calls: string[] = [];
  const fetchImpl = (async (url: string | URL | Request) => {
    calls.push(String(url));
    const next = script.shift();
    if (next === undefined) throw new Error('fetch called more times than scripted');
    if (next === 'throw') throw new TypeError('Failed to fetch');
    return response(next);
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
}

const noSleep = async () => {};
const body = new Blob([new Uint8Array([1, 2, 3])]);

describe('isTransientStatus / classifyStatus', () => {
  it('matches the Rust is_transient: 429 and every 5xx', () => {
    expect(isTransientStatus(429)).toBe(true);
    for (const s of [500, 502, 503, 504, 599]) expect(isTransientStatus(s)).toBe(true);
    for (const s of [200, 204, 400, 401, 403, 404, 409, 413, 428, 600]) {
      expect(isTransientStatus(s)).toBe(false);
    }
  });

  it('classifies 2xx ok, transient retry, other 4xx fatal', () => {
    expect(classifyStatus(200)).toBe('ok');
    expect(classifyStatus(204)).toBe('ok');
    expect(classifyStatus(429)).toBe('retry');
    expect(classifyStatus(503)).toBe('retry');
    expect(classifyStatus(403)).toBe('fatal'); // expired presign
    expect(classifyStatus(404)).toBe('fatal');
    expect(classifyStatus(413)).toBe('fatal');
  });
});

describe('backoffDelayMs', () => {
  it('doubles from the base with ±50% jitter', () => {
    // random() = 0.5 → exactly the nominal delay.
    expect(backoffDelayMs(1, 500, () => 0.5)).toBe(500);
    expect(backoffDelayMs(2, 500, () => 0.5)).toBe(1000);
    expect(backoffDelayMs(3, 500, () => 0.5)).toBe(2000);
    // Jitter bounds.
    expect(backoffDelayMs(2, 500, () => 0)).toBe(500);
    expect(backoffDelayMs(2, 500, () => 1)).toBe(1500);
  });
});

describe('putWithRetry', () => {
  it('succeeds first try without sleeping', async () => {
    const { fetchImpl, calls } = scriptedFetch([200]);
    let slept = 0;
    const out = await putWithRetry('u', body, {
      fetch: fetchImpl,
      sleep: async () => {
        slept++;
      },
    });
    expect(out).toEqual({ ok: true, attempts: 1 });
    expect(calls).toHaveLength(1);
    expect(slept).toBe(0);
  });

  it('retries 5xx and 429 with growing delays, then succeeds', async () => {
    const { fetchImpl, calls } = scriptedFetch([503, 429, 200]);
    const delays: number[] = [];
    const out = await putWithRetry('u', body, {
      fetch: fetchImpl,
      sleep: async (ms) => {
        delays.push(ms);
      },
      random: () => 0.5,
      baseDelayMs: 500,
    });
    expect(out).toEqual({ ok: true, attempts: 3 });
    expect(calls).toHaveLength(3);
    expect(delays).toEqual([500, 1000]);
  });

  it('retries network faults (offline / CORS refusal) up to the budget', async () => {
    const { fetchImpl, calls } = scriptedFetch(['throw', 'throw', 'throw', 'throw']);
    const out = await putWithRetry('u', body, { fetch: fetchImpl, sleep: noSleep });
    expect(calls).toHaveLength(RETRY_ATTEMPTS);
    expect(out.ok).toBe(false);
    if (!out.ok) {
      expect(out.kind).toBe('network');
      expect(out.attempts).toBe(RETRY_ATTEMPTS);
      expect(out.error).toContain('Failed to fetch');
    }
  });

  it('treats a non-429 4xx as terminal without retrying', async () => {
    const { fetchImpl, calls } = scriptedFetch([403]);
    const out = await putWithRetry('u', body, { fetch: fetchImpl, sleep: noSleep });
    expect(calls).toHaveLength(1);
    expect(out).toEqual({
      ok: false,
      kind: 'http',
      status: 403,
      attempts: 1,
      error: 'blob upload failed (403)',
    });
  });

  it('gives up after the budget on persistent 5xx and reports the last status', async () => {
    const { fetchImpl, calls } = scriptedFetch([500, 502, 503, 504]);
    const out = await putWithRetry('u', body, { fetch: fetchImpl, sleep: noSleep });
    expect(calls).toHaveLength(RETRY_ATTEMPTS);
    expect(out).toMatchObject({ ok: false, kind: 'http', status: 504, attempts: RETRY_ATTEMPTS });
  });

  it('never throws — a failing fetch becomes a value the caller can collect', async () => {
    const { fetchImpl } = scriptedFetch(['throw', 500, 404]);
    await expect(
      putWithRetry('u', body, { fetch: fetchImpl, sleep: noSleep }),
    ).resolves.toMatchObject({ ok: false, kind: 'http', status: 404, attempts: 3 });
  });
});
