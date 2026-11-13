#!/usr/bin/env bash
# End-to-end smoke test of the Phase 5 OAuth verify/poll flow against a running
# stack (scripts/oauth-dev.sh). Computes a PKCE pair, starts verification,
# pulls the magic-link code from the server log (NullMailer), clicks it, and
# polls for tokens — exercising the whole O4 polling path server-side.
#
#   ./scripts/oauth-smoke.sh [CALLSIGN] [EMAIL]
set -euo pipefail
cd "$(dirname "$0")/.."

base="${BASE_URL:-http://localhost:8080}"
call="${1:-W6JY}"
email="${2:-dev@example.com}"

ver=$(openssl rand -hex 32)
chal=$(printf %s "$ver" | openssl dgst -sha256 | awk '{print $2}')

echo "▶ verify/start ($call → $email)"
poll=$(curl -fsS "$base/v1/auth/verify/start" -H 'content-type: application/json' \
  -d "{\"callsign\":\"$call\",\"email\":\"$email\",\"pkceChallenge\":\"$chal\"}" | jq -r .pollToken)
echo "  pollToken=$poll"

echo "▶ poll before click (expect HTTP 202)"
curl -s -o /dev/null -w '  HTTP %{http_code}\n' "$base/v1/auth/verify/poll" \
  -H 'content-type: application/json' -d "{\"pollToken\":\"$poll\",\"pkceVerifier\":\"$ver\"}"

echo "▶ reading magic-link code from server log"
log="${SERVER_LOG:-.oauth-dev/server.log}"
code=$(grep -oE 'code=[0-9a-f]{32}' "$log" 2>/dev/null | tail -1 | cut -d= -f2 || true)
if [ -z "${code:-}" ]; then
  echo "  ✗ no code found in $log — is the server running (scripts/oauth-dev.sh) and did you pass an email?"
  exit 1
fi
echo "  code=$code"

echo "▶ verify/complete (click the link)"
curl -s -o /dev/null -w '  HTTP %{http_code}\n' "$base/v1/auth/verify/complete?code=$code"

echo "▶ poll after click (expect HTTP 201 + token pair)"
curl -fsS "$base/v1/auth/verify/poll" -H 'content-type: application/json' \
  -d "{\"pollToken\":\"$poll\",\"pkceVerifier\":\"$ver\"}" | jq .

echo "✓ OAuth verify/poll flow complete"
