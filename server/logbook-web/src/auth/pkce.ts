// PKCE for the magic-link flow. The server verifies `challenge == hex(sha256(
// verifier))` (see auth/tokens.rs::pkce_challenge_for), so the challenge is a
// lowercase hex SHA-256 digest — NOT the RFC 7636 base64url form.

function toHex(buf: ArrayBuffer): string {
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** A high-entropy URL-safe verifier (43+ chars per RFC 7636). */
export function generateVerifier(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  // base64url without padding — a valid verifier alphabet.
  let s = btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** hex(sha256(verifier)) — the exact shape the server stores + compares. */
export async function challengeFor(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return toHex(digest);
}
