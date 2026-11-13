// Bounded retry with exponential backoff for the blob-upload path (CAR-322).
//
// Mirrors the Rust client (`cw-sync/src/http_transport.rs::with_retry` /
// `is_transient`): a 429 or any 5xx is transient and worth another go, every
// other non-2xx is terminal for that request. Browser `fetch` additionally
// rejects (TypeError) on network faults and CORS refusals without ever giving
// us a status; those are retried too, since a flaky link is the common case
// and a CORS misconfiguration simply exhausts the budget and reports back.
//
// This module deliberately imports nothing from the app (no WASM, no session)
// so it can be unit-tested under plain Node.

/** Attempts per upload: 500ms → 1s → 2s between them (~3.5s worst case before jitter). */
export const RETRY_ATTEMPTS = 4;
export const RETRY_BASE_DELAY_MS = 500;

/** The Rust `is_transient`: rate-limited or server-side failure. */
export function isTransientStatus(status: number): boolean {
  return status === 429 || (status >= 500 && status <= 599);
}

export type StatusClass = 'ok' | 'retry' | 'fatal';

/** Decide what a PUT's HTTP status means for the retry loop. */
export function classifyStatus(status: number): StatusClass {
  if (status >= 200 && status <= 299) return 'ok';
  return isTransientStatus(status) ? 'retry' : 'fatal';
}

/**
 * Delay before retry number `attempt` (1-based: the wait after the first
 * failure is attempt 1). Doubles from `base` with ±50% jitter so a burst of
 * parallel tabs/devices doesn't re-hit R2 in lockstep.
 */
export function backoffDelayMs(
  attempt: number,
  base: number = RETRY_BASE_DELAY_MS,
  random: () => number = Math.random,
): number {
  const exp = base * 2 ** Math.max(0, attempt - 1);
  return Math.round(exp * (0.5 + random()));
}

export type UploadOutcome =
  | { ok: true; attempts: number }
  | { ok: false; kind: 'http'; status: number; attempts: number; error: string }
  | { ok: false; kind: 'network'; attempts: number; error: string };

/** Injection points for tests; production callers use the defaults. */
export interface RetryDeps {
  fetch?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
  attempts?: number;
  baseDelayMs?: number;
}

const realSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * PUT `body` to `url` with bounded retry. Never throws: every outcome —
 * success, terminal 4xx, or an exhausted budget — comes back as a value so a
 * caller looping over many uploads can attempt all of them and report
 * per-entry results. `body` must be re-sendable (a Blob is; a stream isn't).
 */
export async function putWithRetry(
  url: string,
  body: Blob,
  deps: RetryDeps = {},
): Promise<UploadOutcome> {
  const doFetch = deps.fetch ?? fetch;
  const sleep = deps.sleep ?? realSleep;
  const random = deps.random ?? Math.random;
  const attempts = deps.attempts ?? RETRY_ATTEMPTS;
  const base = deps.baseDelayMs ?? RETRY_BASE_DELAY_MS;

  for (let attempt = 1; attempt <= attempts; attempt++) {
    const last = attempt === attempts;
    try {
      const resp = await doFetch(url, { method: 'PUT', body });
      const cls = classifyStatus(resp.status);
      if (cls === 'ok') return { ok: true, attempts: attempt };
      if (cls === 'fatal' || last) {
        return {
          ok: false,
          kind: 'http',
          status: resp.status,
          attempts: attempt,
          error: `blob upload failed (${resp.status})`,
        };
      }
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      if (last) {
        return { ok: false, kind: 'network', attempts: attempt, error: `network error: ${message}` };
      }
    }
    await sleep(backoffDelayMs(attempt, base, random));
  }
  // The loop always returns on its final iteration.
  throw new Error('unreachable: retry budget must be ≥ 1');
}
