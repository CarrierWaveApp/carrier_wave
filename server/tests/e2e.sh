#!/usr/bin/env bash
# End-to-end tests for the challenges server API.
# Requires: BASE_URL and ADMIN_TOKEN environment variables.
# Exits non-zero on first failure.

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
ADMIN_TOKEN="${ADMIN_TOKEN:-e2e-admin-token}"

PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

assert_status() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $description (HTTP $actual)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — expected $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

get() {
  curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$1"
}

get_json() {
  curl -sf "$BASE_URL$1"
}

post() {
  local path="$1"
  shift
  curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL$path" \
    -H "Content-Type: application/json" "$@"
}

post_json() {
  local path="$1"
  shift
  curl -sf -X POST "$BASE_URL$path" \
    -H "Content-Type: application/json" "$@"
}

delete() {
  curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL$1" \
    "${@:2}"
}

put() {
  local path="$1"
  shift
  curl -s -o /dev/null -w "%{http_code}" -X PUT "$BASE_URL$path" \
    -H "Content-Type: application/json" "$@"
}

put_json() {
  local path="$1"
  shift
  curl -sf -X PUT "$BASE_URL$path" \
    -H "Content-Type: application/json" "$@"
}

get_auth() {
  local path="$1"
  shift
  curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$path" "$@"
}

get_auth_json() {
  local path="$1"
  shift
  curl -sf "$BASE_URL$path" "$@"
}

admin_header=(-H "Authorization: Bearer $ADMIN_TOKEN")

# ── Health ───────────────────────────────────────────────────────────────────

echo "=== Health ==="
assert_status "GET /v1/health" 200 "$(get /v1/health)"

health_body=$(get_json /v1/health)
if echo "$health_body" | grep -q '"status"'; then
  echo "  PASS: health response contains status field"
  PASS=$((PASS + 1))
else
  echo "  FAIL: health response missing status field"
  FAIL=$((FAIL + 1))
fi

# ── Public endpoints (empty state) ──────────────────────────────────────────

echo "=== Public endpoints ==="
assert_status "GET /v1/challenges" 200 "$(get /v1/challenges)"
assert_status "GET /v1/programs" 200 "$(get /v1/programs)"
assert_status "GET /v1/pota/stats/status" 200 "$(get /v1/pota/stats/status)"
assert_status "GET /v1/pota/stats/rankings/activators" 200 "$(get '/v1/pota/stats/rankings/activators?limit=10')"

# ── Admin auth ──────────────────────────────────────────────────────────────

echo "=== Admin auth ==="
assert_status "POST /v1/admin/challenges (no auth)" 401 \
  "$(post /v1/admin/challenges -d '{"name":"test"}')"

# ── Challenge CRUD flow ─────────────────────────────────────────────────────

echo "=== Challenge lifecycle ==="

# Create a challenge
challenge_response=$(post_json /v1/admin/challenges \
  "${admin_header[@]}" \
  -d '{
    "name": "E2E Test Challenge",
    "description": "Created by e2e tests",
    "category": "award",
    "type": "collection",
    "configuration": {"target_count": 10}
  }')

challenge_id=$(echo "$challenge_response" | jq -r '.data.id')

if [ -n "$challenge_id" ] && [ "$challenge_id" != "null" ]; then
  echo "  PASS: Created challenge $challenge_id"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Could not create challenge"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

# Get the challenge
assert_status "GET /v1/challenges/$challenge_id" 200 \
  "$(get "/v1/challenges/$challenge_id")"

# Get leaderboard
assert_status "GET /v1/challenges/$challenge_id/leaderboard" 200 \
  "$(get "/v1/challenges/$challenge_id/leaderboard")"

# Join the challenge (get a device token first)
join_response=$(post_json "/v1/challenges/$challenge_id/join" \
  -d '{"callsign": "E2ETEST"}')
device_token=$(echo "$join_response" | jq -r '.data.deviceToken')

if [ -n "$device_token" ] && [ "$device_token" != "null" ]; then
  echo "  PASS: Joined challenge, got device token"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Could not join challenge"
  FAIL=$((FAIL + 1))
fi

# Report progress (auth required)
if [ -n "$device_token" ] && [ "$device_token" != "null" ]; then
  auth_header=(-H "Authorization: Bearer $device_token")

  progress_status=$(post "/v1/challenges/$challenge_id/progress" \
    "${auth_header[@]}" \
    -d '{"completedGoals": ["K1ABC"], "currentValue": 1, "qualifyingQsoCount": 1}')
  assert_status "POST progress (authenticated)" 200 "$progress_status"

  # Get own progress
  assert_status "GET /v1/challenges/$challenge_id/progress" 200 \
    "$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/v1/challenges/$challenge_id/progress" "${auth_header[@]}")"

  # Leave challenge
  leave_status=$(delete "/v1/challenges/$challenge_id/leave" "${auth_header[@]}")
  assert_status "DELETE /v1/challenges/$challenge_id/leave" 204 "$leave_status"
fi

# Admin delete
admin_delete_status=$(delete "/v1/admin/challenges/$challenge_id" "${admin_header[@]}")
assert_status "DELETE /v1/admin/challenges/$challenge_id (admin)" 204 "$admin_delete_status"

# Verify deleted
assert_status "GET /v1/challenges/$challenge_id (after delete)" 404 \
  "$(get "/v1/challenges/$challenge_id")"

# ── Club CRUD lifecycle ──────────────────────────────────────────────────────

echo "=== Club lifecycle ==="

# Create a club
club_response=$(post_json /v1/admin/clubs \
  "${admin_header[@]}" \
  -d '{
    "name": "E2E Test Club",
    "description": "Created by e2e tests"
  }')

club_id=$(echo "$club_response" | jq -r '.data.id')

if [ -n "$club_id" ] && [ "$club_id" != "null" ]; then
  echo "  PASS: Created club $club_id"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Could not create club"
  FAIL=$((FAIL + 1))
fi

# List clubs
assert_status "GET /v1/admin/clubs" 200 \
  "$(get_auth /v1/admin/clubs "${admin_header[@]}")"

# Update club
if [ -n "$club_id" ] && [ "$club_id" != "null" ]; then
  update_status=$(put "/v1/admin/clubs/$club_id" \
    "${admin_header[@]}" \
    -d '{"name": "E2E Updated Club", "description": "Updated"}')
  assert_status "PUT /v1/admin/clubs/$club_id" 200 "$update_status"

  # Add members to the club
  add_members_status=$(post "/v1/admin/clubs/$club_id/members" \
    "${admin_header[@]}" \
    -d '{"members": [{"callsign": "W1AW"}, {"callsign": "N5XX"}, {"callsign": "K1ABC"}]}')
  assert_status "POST /v1/admin/clubs/$club_id/members" 201 "$add_members_status"

  # List club members
  assert_status "GET /v1/admin/clubs/$club_id/members" 200 \
    "$(get_auth "/v1/admin/clubs/$club_id/members" "${admin_header[@]}")"

  # Update member role
  role_status=$(put "/v1/admin/clubs/$club_id/members/W1AW" \
    "${admin_header[@]}" \
    -d '{"role": "admin"}')
  assert_status "PUT /v1/admin/clubs/$club_id/members/W1AW (role)" 200 "$role_status"

  # Remove a member
  remove_member_status=$(delete "/v1/admin/clubs/$club_id/members/K1ABC" "${admin_header[@]}")
  assert_status "DELETE /v1/admin/clubs/$club_id/members/K1ABC" 204 "$remove_member_status"

  # Delete club
  delete_club_status=$(delete "/v1/admin/clubs/$club_id" "${admin_header[@]}")
  assert_status "DELETE /v1/admin/clubs/$club_id" 204 "$delete_club_status"
fi

# Club admin auth (no token)
assert_status "GET /v1/admin/clubs (no auth)" 401 "$(get /v1/admin/clubs)"

# ── Social / Friends lifecycle ──────────────────────────────────────────────

echo "=== Social / Friends ==="

# Create two users by joining a challenge, so we have device tokens
# First, create a challenge for this test
social_challenge=$(post_json /v1/admin/challenges \
  "${admin_header[@]}" \
  -d '{
    "name": "Social Test Challenge",
    "description": "For friend tests",
    "category": "award",
    "type": "collection",
    "configuration": {"target_count": 5}
  }')
social_challenge_id=$(echo "$social_challenge" | jq -r '.data.id')

if [ -n "$social_challenge_id" ] && [ "$social_challenge_id" != "null" ]; then
  # User A joins
  join_a=$(post_json "/v1/challenges/$social_challenge_id/join" \
    -d '{"callsign": "E2EUSER1"}')
  token_a=$(echo "$join_a" | jq -r '.data.deviceToken')

  # User B joins
  join_b=$(post_json "/v1/challenges/$social_challenge_id/join" \
    -d '{"callsign": "E2EUSER2"}')
  token_b=$(echo "$join_b" | jq -r '.data.deviceToken')

  if [ -n "$token_a" ] && [ "$token_a" != "null" ] && [ -n "$token_b" ] && [ "$token_b" != "null" ]; then
    auth_a=(-H "Authorization: Bearer $token_a")
    auth_b=(-H "Authorization: Bearer $token_b")

    # Get invite link for User A
    invite_link_status=$(get_auth /v1/friends/invite-link "${auth_a[@]}")
    assert_status "GET /v1/friends/invite-link (User A)" 200 "$invite_link_status"

    invite_response=$(get_auth_json /v1/friends/invite-link "${auth_a[@]}")
    invite_token=$(echo "$invite_response" | jq -r '.data.token')

    if [ -n "$invite_token" ] && [ "$invite_token" != "null" ]; then
      echo "  PASS: Got invite token for User A"
      PASS=$((PASS + 1))

      # User B creates friend request via invite token
      friend_req_status=$(post "/v1/friends/requests" \
        "${auth_b[@]}" \
        -d "{\"inviteToken\": \"$invite_token\"}")
      assert_status "POST /v1/friends/requests (User B via invite)" 201 "$friend_req_status"
    else
      echo "  FAIL: No invite token returned"
      FAIL=$((FAIL + 1))
    fi

    # List pending requests for User A
    pending_status=$(get_auth /v1/friends/requests/pending "${auth_a[@]}")
    assert_status "GET /v1/friends/requests/pending (User A)" 200 "$pending_status"

    # List friends (should be empty or have the new friend if auto-accepted)
    friends_status=$(get_auth /v1/friends "${auth_a[@]}")
    assert_status "GET /v1/friends (User A)" 200 "$friends_status"
  else
    echo "  FAIL: Could not create test users for social tests"
    FAIL=$((FAIL + 1))
  fi

  # Cleanup: delete social test challenge
  delete "/v1/admin/challenges/$social_challenge_id" "${admin_header[@]}" > /dev/null 2>&1
fi

# Friends endpoints require auth
assert_status "GET /v1/friends/invite-link (no auth)" 401 "$(get /v1/friends/invite-link)"
assert_status "GET /v1/friends (no auth)" 401 "$(get /v1/friends)"

# ── RBN endpoints ───────────────────────────────────────────────────────────

echo "=== RBN endpoints ==="
assert_status "GET /v1/rbn/spots" 200 "$(get /v1/rbn/spots)"
assert_status "GET /v1/rbn/stats" 200 "$(get /v1/rbn/stats)"
assert_status "GET /v1/rbn/skimmers" 200 "$(get /v1/rbn/skimmers)"

# Verify RBN spots response shape
rbn_spots=$(get_json /v1/rbn/spots)
if echo "$rbn_spots" | grep -q '"spots"'; then
  echo "  PASS: RBN spots response has 'spots' field"
  PASS=$((PASS + 1))
else
  echo "  FAIL: RBN spots response missing 'spots' field"
  FAIL=$((FAIL + 1))
fi

rbn_stats=$(get_json /v1/rbn/stats)
if echo "$rbn_stats" | grep -q '"total_spots"'; then
  echo "  PASS: RBN stats response has 'total_spots' field"
  PASS=$((PASS + 1))
else
  echo "  FAIL: RBN stats response missing 'total_spots' field"
  FAIL=$((FAIL + 1))
fi

# ── GIS endpoints ───────────────────────────────────────────────────────────

echo "=== GIS endpoints ==="
assert_status "GET /v1/parks/boundaries (no params)" 200 \
  "$(get '/v1/parks/boundaries?refs=US-0001')"
assert_status "GET /v1/trails (no params)" 200 \
  "$(get '/v1/trails?refs=NHT-LC')"
assert_status "GET /v1/trails/status" 200 "$(get /v1/trails/status)"

# ── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
