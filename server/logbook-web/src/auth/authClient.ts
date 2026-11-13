// The magic-link + PKCE login flow, reused verbatim from the iOS account flow:
//
//   1. startVerification(callsign, email?) → commits a PKCE challenge, server
//      emails a link, returns an opaque poll token.
//   2. The user clicks the emailed link (opens verify/complete on the server).
//   3. pollOnce(pollToken) polls verify/poll with the PKCE verifier; while the
//      link is unclicked it's `pending`, then it mints the JWT token pair.
//
// The verifier never leaves the browser; it binds redemption to this tab.

import { generateVerifier, challengeFor } from './pkce';
import { saveTokens } from './session';

export interface PendingVerification {
  pollToken: string;
  verifier: string;
}

export async function startVerification(
  callsign: string,
  email?: string,
): Promise<PendingVerification> {
  const verifier = generateVerifier();
  const pkceChallenge = await challengeFor(verifier);
  const resp = await fetch('/v1/auth/verify/start', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      callsign: callsign.trim().toUpperCase(),
      email: email?.trim() || undefined,
      pkceChallenge,
    }),
  });
  if (resp.status !== 202) {
    throw new Error(`verify/start failed (${resp.status})`);
  }
  const { pollToken } = (await resp.json()) as { pollToken: string };
  return { pollToken, verifier };
}

export type PollResult = 'pending' | 'authenticated';

export async function pollOnce(p: PendingVerification): Promise<PollResult> {
  const resp = await fetch('/v1/auth/verify/poll', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ pollToken: p.pollToken, pkceVerifier: p.verifier }),
  });
  if (resp.status === 202) return 'pending';
  if (resp.status === 201) {
    saveTokens(await resp.json());
    return 'authenticated';
  }
  // 204 = attach-to-existing (no tokens) — not reachable from this unauthed
  // web login, but treat defensively as an error rather than a silent success.
  throw new Error(`verify/poll failed (${resp.status})`);
}
