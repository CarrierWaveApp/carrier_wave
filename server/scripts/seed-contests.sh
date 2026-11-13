#!/usr/bin/env bash
# Seed contest definitions from the example JSON files into the database
# via the admin API endpoint.
#
# Usage:
#   ./scripts/seed-contests.sh                              # localhost:3000
#   ./scripts/seed-contests.sh https://activities.carrierwave.app
#
# Requires ADMIN_TOKEN env var for the admin endpoint auth.

set -euo pipefail

BASE_URL="${1:-http://localhost:3000}"
ENDPOINT="${BASE_URL}/v1/admin/contests"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLES_DIR="${SCRIPT_DIR}/../docs/examples/contests"

if [ -z "${ADMIN_TOKEN:-}" ]; then
  echo "Error: ADMIN_TOKEN env var is required" >&2
  exit 1
fi

# Auto-discover all contest JSON files, excluding the schema file and
# the sample bundle (which wraps multiple contests for documentation).
SKIP_FILES="schema.json sample-bundle.json"

echo "Seeding contest definitions to ${ENDPOINT}"
echo ""

for path in "${EXAMPLES_DIR}"/*.json; do
  file="$(basename "$path")"

  # Skip non-contest files.
  if echo "$SKIP_FILES" | grep -qw "$file"; then
    continue
  fi

  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${ENDPOINT}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -d @"${path}")

  if [ "$status" = "200" ]; then
    echo "  OK    ${file}"
  else
    echo "  FAIL  ${file} (HTTP ${status})"
    # Show response body on failure
    curl -s -X POST "${ENDPOINT}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -d @"${path}" | head -5
    echo ""
  fi
done

echo ""
echo "Done. Verify at ${BASE_URL}/v1/contests"
