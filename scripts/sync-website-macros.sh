#!/usr/bin/env bash
# Sync the public macros catalog from the activities-server into the Hugo
# manual site (CAR-273). Writes:
#   website/manual-src/data/macros.json
#       — full list response, consumed by /manual/macros/ listing
#   website/manual-src/content/macros/<slug>.md
#       — one content file per approved macro, populated from
#         GET /v1/macros/:slug; powers /manual/m/<slug>/ pages.
#
# Stale per-slug files are removed if their slug no longer appears in the
# upstream catalog (handles withdrawals / tombstones without a separate
# tombstones pass).
#
# Usage:
#   scripts/sync-website-macros.sh                  # uses production API
#   API_BASE=http://localhost:8080 scripts/sync-website-macros.sh
#
# Run before `hugo --gc --minify` in the deploy pipeline.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE="${API_BASE:-https://api.carrierwave.app}"
LIMIT="${LIMIT:-200}"

DATA_FILE="${REPO_ROOT}/website/manual-src/data/macros.json"
CONTENT_DIR="${REPO_ROOT}/website/manual-src/content/macros"

for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null; then
    echo "error: '$cmd' is required" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$DATA_FILE")" "$CONTENT_DIR"

echo "==> fetching $API_BASE/v1/macros?limit=$LIMIT"
list_json="$(curl -fsS "${API_BASE}/v1/macros?limit=${LIMIT}")"
echo "$list_json" > "$DATA_FILE"

slugs="$(echo "$list_json" | jq -r '.entries[].slug')"

# Track upstream slugs so we can prune stale content files later.
upstream_tmp="$(mktemp)"
trap 'rm -f "$upstream_tmp"' EXIT

count=0
while IFS= read -r slug; do
  [ -z "$slug" ] && continue
  echo "$slug" >> "$upstream_tmp"
  echo "==> fetching $slug"
  doc="$(curl -fsS "${API_BASE}/v1/macros/${slug}")"

  # Hugo accepts JSON front matter when a content file begins with `{`.
  # The whole document goes in so templates can read .Params.* uniformly;
  # the Markdown body is empty — rendering lives in layouts/macros/single.html.
  echo "$doc" | jq '{
    title: .spec.name,
    slug: .slug,
    description: .spec.description,
    icon: .spec.icon,
    tags: .spec.tags,
    applies_to: .spec.applies_to,
    capabilities: .spec.capabilities,
    args: .spec.args,
    steps: .spec.steps,
    format: .format,
    version: .version,
    published_at: .published_at,
    updated_at: .updated_at,
    author_callsign: .author_callsign
  }' > "${CONTENT_DIR}/${slug}.md"

  count=$((count + 1))
done <<< "$slugs"

# Prune content files for slugs no longer in the upstream catalog. We only
# touch files that look like sync output; _index.md is left alone.
find "$CONTENT_DIR" -maxdepth 1 -type f -name '*.md' ! -name '_index.md' -print0 |
while IFS= read -r -d '' file; do
  fname="$(basename "$file" .md)"
  if ! grep -Fxq "$fname" "$upstream_tmp"; then
    echo "==> removing stale: $fname"
    rm -f "$file"
  fi
done

echo "==> wrote $count macro(s) from $API_BASE"
