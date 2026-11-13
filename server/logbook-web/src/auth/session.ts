// Token session: stores the JWT access/refresh pair, adds the Bearer header to
// API calls, and transparently rotates on a 401. Tokens live in sessionStorage
// (cleared when the tab closes) — never localStorage, to limit exposure.
//
// The sync passphrase / data key are deliberately NOT handled here; they live in
// memory only (see AppState) and never touch storage.

const ACCESS_KEY = 'cw_logbook_access';
const REFRESH_KEY = 'cw_logbook_refresh';

interface TokenPair {
  access: string;
  refresh: string;
  expiresIn: number;
}

export function saveTokens(t: TokenPair): void {
  sessionStorage.setItem(ACCESS_KEY, t.access);
  sessionStorage.setItem(REFRESH_KEY, t.refresh);
}

export function clearTokens(): void {
  sessionStorage.removeItem(ACCESS_KEY);
  sessionStorage.removeItem(REFRESH_KEY);
}

export function getAccess(): string | null {
  return sessionStorage.getItem(ACCESS_KEY);
}

export function isLoggedIn(): boolean {
  return getAccess() !== null;
}

async function refreshAccess(): Promise<boolean> {
  const refresh = sessionStorage.getItem(REFRESH_KEY);
  if (!refresh) return false;
  const resp = await fetch('/v1/auth/token/refresh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh }),
  });
  if (!resp.ok) {
    clearTokens();
    return false;
  }
  saveTokens((await resp.json()) as TokenPair);
  return true;
}

/**
 * Human-readable failure for a sync API response. `/v1/sync/*` requires an
 * account-backed session and refuses anything else with 403 ACCOUNT_REQUIRED —
 * surface that as a sign-in problem rather than a bare status code.
 */
export async function syncFailure(resp: Response, what: string): Promise<Error> {
  let code: string | undefined;
  try {
    code = ((await resp.json()) as { error?: { code?: string } }).error?.code;
  } catch {
    // non-JSON body — fall through to the generic message
  }
  if (resp.status === 403 && code === 'ACCOUNT_REQUIRED') {
    return new Error(
      'Sync requires a signed-in Carrier Wave account. Sign out, then sign ' +
        'back in with your callsign to get a fresh email verification link.',
    );
  }
  return new Error(`${what} failed (${resp.status})`);
}

/**
 * fetch() with the Bearer access token attached. On a 401 it rotates the
 * refresh token once and retries; a second 401 (or no refresh) clears the
 * session and throws so the UI can bounce to login.
 */
export async function authFetch(input: string, init: RequestInit = {}): Promise<Response> {
  const withAuth = (token: string): RequestInit => ({
    ...init,
    headers: { ...(init.headers ?? {}), Authorization: `Bearer ${token}` },
  });

  const token = getAccess();
  if (!token) throw new Error('not authenticated');

  let resp = await fetch(input, withAuth(token));
  if (resp.status === 401 && (await refreshAccess())) {
    resp = await fetch(input, withAuth(getAccess()!));
  }
  if (resp.status === 401) {
    clearTokens();
    throw new Error('session expired');
  }
  return resp;
}
