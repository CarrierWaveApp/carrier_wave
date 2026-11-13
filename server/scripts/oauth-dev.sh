#!/usr/bin/env bash
# Phase 5 OAuth local stack: PostGIS (Docker) + activities server (host).
#
# Brings up the PostGIS container, generates a persistent dev Ed25519 keypair
# (under .oauth-dev/, gitignored), and runs the server on the host with the
# `/v1/auth/*` routes enabled and every network background task disabled. The
# magic-link code is logged (NullMailer) to the terminal and to
# .oauth-dev/server.log, where scripts/oauth-smoke.sh reads it.
#
#   ./scripts/oauth-dev.sh        # up DB + run server (foreground)
set -euo pipefail
cd "$(dirname "$0")/.."

compose="docker compose -f docker-compose.oauth.yml"
keydir=.oauth-dev
mkdir -p "$keydir"

if [ ! -f "$keydir/ed25519.pem" ]; then
  openssl genpkey -algorithm ed25519 -out "$keydir/ed25519.pem"
  openssl pkey -in "$keydir/ed25519.pem" -pubout -out "$keydir/ed25519.pub.pem"
  echo "Generated dev Ed25519 keypair in $keydir/ (gitignored)"
fi

echo "Starting PostGIS…"
$compose up -d db
printf "Waiting for db to be healthy"
for _ in $(seq 1 40); do
  cid=$($compose ps -q db)
  status=$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo starting)
  [ "$status" = "healthy" ] && break
  printf "."; sleep 1
done
echo " ${status:-?}"

export JWT_ED25519_PRIVATE_PEM="$(cat "$keydir/ed25519.pem")"
export JWT_ED25519_PUBLIC_PEM="$(cat "$keydir/ed25519.pub.pem")"
export JWT_KID=dev
export DATABASE_URL="postgres://challenges:challenges@localhost:5433/challenges"
export ADMIN_TOKEN=dev-admin-token
export BASE_URL="http://localhost:8080"
export PORT=8080
export RUST_LOG="info,auth_magic_link=info"
# OAuth-only: no network background tasks.
export SPOTS_ENABLED=false POTA_AGGREGATOR_ENABLED=false SOTA_AGGREGATOR_ENABLED=false \
  POTA_STATS_AGGREGATOR_ENABLED=false PARK_BOUNDARIES_ENABLED=false \
  POLISH_PARK_BOUNDARIES_ENABLED=false HISTORIC_TRAILS_ENABLED=false \
  CALLSIGN_ENRICHMENT_AGGREGATOR_ENABLED=false ACHIEVEMENT_EVALUATOR_ENABLED=false \
  MACROS_RETENTION_ENABLED=false RBN_PROXY_ENABLED=false PROPAGATION_ENABLED=false \
  SNAPSHOT_ENABLED=false

echo "Starting server on http://localhost:8080 (logs → $keydir/server.log)"
echo "  (Ctrl+C stops the server; run '$compose down' to stop the DB.)"
cargo run 2>&1 | tee "$keydir/server.log"
