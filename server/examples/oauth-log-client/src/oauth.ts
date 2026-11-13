// OAuth 2.0 device authorization grant (RFC 8628) + token refresh.
//
// The device flow is used rather than the authorization-code flow because a CLI
// has nowhere to receive a redirect. A GUI application should use
// authorization_code + PKCE instead; see docs/features/oauth-api.md.

import { readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

/**
 * Where tokens live.
 *
 * Defaults to an absolute path under $HOME rather than the working directory:
 * anything embedding this (an MCP server, a cron job) is launched with a cwd it
 * did not choose, and a relative path would silently produce a second, empty
 * token store instead of finding the one `login` wrote.
 */
const TOKEN_FILE = process.env.CW_TOKEN_FILE ?? join(homedir(), '.cw-tokens.json');

/** Absolute path tokens are read from and written to. */
export const tokenFilePath = (): string => TOKEN_FILE;

export interface Tokens {
  access_token: string;
  refresh_token: string;
  scope: string;
  /** Unix ms when the access token stops being usable. */
  expires_at: number;
}

export interface Config {
  baseUrl: string;
  clientId: string;
}

export function configFromEnv(): Config {
  const clientId = process.env.CW_CLIENT_ID;
  if (!clientId) {
    throw new Error('CW_CLIENT_ID is not set (a registered client_id is required)');
  }
  return {
    baseUrl: (process.env.CW_BASE_URL ?? 'https://activities.carrierwave.app').replace(/\/$/, ''),
    clientId,
  };
}

interface TokenResponse {
  access_token: string;
  refresh_token: string;
  scope: string;
  expires_in: number;
}

interface OAuthErrorBody {
  error: string;
  error_description?: string;
}

/**
 * Run the device flow to completion.
 *
 * Honors the two RFC 8628 backoff signals. `slow_down` is not advisory — ignore
 * it and the server keeps returning it, so an impatient client makes no
 * progress at all.
 */
export async function login(config: Config, scope: string): Promise<Tokens> {
  const startResp = await fetch(`${config.baseUrl}/v1/oauth/device/code`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: config.clientId, scope }),
  });
  if (!startResp.ok) {
    throw new Error(`device authorization failed: ${await describe(startResp)}`);
  }
  const start = (await startResp.json()) as {
    device_code: string;
    user_code: string;
    verification_uri: string;
    expires_in: number;
    interval: number;
  };

  console.log(`\n  Open: ${start.verification_uri}`);
  console.log(`  Code: ${start.user_code}\n`);
  console.log('Waiting for approval…');

  let interval = start.interval;
  const deadline = Date.now() + start.expires_in * 1000;

  while (Date.now() < deadline) {
    await sleep(interval * 1000);

    const resp = await fetch(`${config.baseUrl}/v1/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
        client_id: config.clientId,
        device_code: start.device_code,
      }),
    });

    if (resp.ok) {
      return await saveTokens((await resp.json()) as TokenResponse);
    }

    const body = (await resp.json().catch(() => ({}))) as Partial<OAuthErrorBody>;
    switch (body.error) {
      case 'authorization_pending':
        break;
      case 'slow_down':
        interval += 5;
        break;
      case 'access_denied':
        throw new Error('The request was declined.');
      case 'expired_token':
        throw new Error('The code expired. Run login again.');
      default:
        throw new Error(`token exchange failed: ${body.error_description ?? body.error}`);
    }
  }

  throw new Error('Timed out waiting for approval.');
}

/**
 * A valid access token, refreshing if needed.
 *
 * Refresh tokens ROTATE: the response carries a new one and the presented token
 * dies. Persist the new value before doing anything else — losing it means
 * re-authorizing, and presenting a rotated token twice is treated as theft and
 * revokes the entire family.
 */
export async function accessToken(config: Config): Promise<string> {
  const tokens = await loadTokens();

  // Refresh a minute early rather than racing the expiry.
  if (Date.now() < tokens.expires_at - 60_000) return tokens.access_token;

  const resp = await fetch(`${config.baseUrl}/v1/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: config.clientId,
      refresh_token: tokens.refresh_token,
    }),
  });
  if (!resp.ok) {
    throw new Error(
      `refresh failed (${await describe(resp)}). The user may have disconnected this ` +
        'application; run login again.',
    );
  }

  const refreshed = await saveTokens((await resp.json()) as TokenResponse);
  return refreshed.access_token;
}

/** fetch() with the bearer token attached. */
export async function api(
  config: Config,
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  const token = await accessToken(config);
  return fetch(`${config.baseUrl}${path}`, {
    ...init,
    headers: { ...(init.headers ?? {}), Authorization: `Bearer ${token}` },
  });
}

async function saveTokens(response: TokenResponse): Promise<Tokens> {
  const tokens: Tokens = {
    access_token: response.access_token,
    refresh_token: response.refresh_token,
    scope: response.scope,
    expires_at: Date.now() + response.expires_in * 1000,
  };
  // Plaintext on disk. A real client uses the OS keychain.
  await writeFile(TOKEN_FILE, JSON.stringify(tokens, null, 2), { mode: 0o600 });
  return tokens;
}

async function loadTokens(): Promise<Tokens> {
  try {
    return JSON.parse(await readFile(TOKEN_FILE, 'utf8')) as Tokens;
  } catch {
    throw new Error(`No saved tokens at ${TOKEN_FILE}. Run the login command first.`);
  }
}

async function describe(resp: Response): Promise<string> {
  const body = (await resp.json().catch(() => ({}))) as Partial<OAuthErrorBody>;
  return body.error_description ?? body.error ?? `HTTP ${resp.status}`;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
