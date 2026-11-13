// Account/session management: list the account's active sessions and revoke
// them all. Both hit the authenticated `/v1/auth/*` routes through authFetch,
// which attaches the Bearer access token and rotates on a 401.

import { authFetch } from './session';

export interface Session {
  id: string;
  deviceName: string | null;
  platform: string | null;
  createdAt: string; // ISO 8601 (UTC)
  lastSeenAt: string; // ISO 8601 (UTC)
}

/** GET /v1/auth/devices — the account's active sessions, newest-seen first. */
export async function listSessions(): Promise<Session[]> {
  const resp = await authFetch('/v1/auth/devices');
  if (!resp.ok) throw new Error(`Could not load sessions (${resp.status})`);
  const body = (await resp.json()) as { data: Session[] };
  return body.data;
}

/**
 * POST /v1/auth/logout/all — revoke every device and bump the account kill
 * epoch, so all outstanding access tokens (including this tab's) are rejected on
 * next use. The caller must clear local tokens and bounce to login afterward.
 */
export async function logoutAllSessions(): Promise<void> {
  const resp = await authFetch('/v1/auth/logout/all', { method: 'POST' });
  if (!resp.ok) throw new Error(`Sign out everywhere failed (${resp.status})`);
}
