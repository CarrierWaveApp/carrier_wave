#!/usr/bin/env bash
#
# Seed the staging activities database with one operator's clubs and the FULL
# member rosters for those clubs, copied from the production database.
#
# The staging DB (`activities_staging`) is provisioned empty, so the app syncs
# "0 clubs" against staging even for operators who belong to many clubs in
# production. This script copies a single callsign's clubs + every member of
# those clubs from prod into staging so club sync and callsign-notes enrichment
# have real data to exercise.
#
# Both databases live on the same Postgres instance (the activities host), so
# this is run THERE as a user that can `sudo -u postgres`. It is idempotent:
# clubs upsert on their primary key (UUIDs are preserved so club_members FKs
# line up) and member rows are inserted ON CONFLICT DO NOTHING.
#
# Requirements: psql, sudo access to the `postgres` role.
# Usage: ./seed-staging-clubs.sh W6JY
set -euo pipefail

CALL="${1:?usage: seed-staging-clubs.sh CALLSIGN}"
CALL="${CALL^^}"

PROD_DB="${PROD_DB:-activities}"
STAGING_DB="${STAGING_DB:-activities_staging}"
PSQL=(sudo -u postgres psql -v ON_ERROR_STOP=1)

CLUBS_CSV="$(mktemp /tmp/seed_clubs.XXXXXX.csv)"
MEMBERS_CSV="$(mktemp /tmp/seed_members.XXXXXX.csv)"
trap 'rm -f "$CLUBS_CSV" "$MEMBERS_CSV"' EXIT

# 1. Export the operator's clubs (preserve UUIDs so member FKs line up) and the
#    full member rosters for those clubs, straight from production.
"${PSQL[@]}" -d "$PROD_DB" -c "\copy (SELECT id,name,callsign,description,notes_url,notes_title FROM clubs WHERE id IN (SELECT club_id FROM club_members WHERE callsign='$CALL')) TO '$CLUBS_CSV' WITH CSV"
"${PSQL[@]}" -d "$PROD_DB" -c "\copy (SELECT club_id,callsign,role FROM club_members WHERE club_id IN (SELECT club_id FROM club_members WHERE callsign='$CALL')) TO '$MEMBERS_CSV' WITH CSV"

echo "Exported $(wc -l < "$CLUBS_CSV") clubs and $(wc -l < "$MEMBERS_CSV") member rows for $CALL."

# 2. Load into staging via temp tables so the copy is idempotent.
"${PSQL[@]}" -d "$STAGING_DB" <<SQL
BEGIN;

CREATE TEMP TABLE _seed_clubs (
  id uuid, name text, callsign text, description text, notes_url text, notes_title text
) ON COMMIT DROP;
\copy _seed_clubs (id,name,callsign,description,notes_url,notes_title) FROM '$CLUBS_CSV' WITH CSV
INSERT INTO clubs (id,name,callsign,description,notes_url,notes_title)
  SELECT id,name,callsign,description,notes_url,notes_title FROM _seed_clubs
  ON CONFLICT (id) DO UPDATE SET
    name        = EXCLUDED.name,
    callsign    = EXCLUDED.callsign,
    description = EXCLUDED.description,
    notes_url   = EXCLUDED.notes_url,
    notes_title = EXCLUDED.notes_title,
    updated_at  = now();

CREATE TEMP TABLE _seed_members (
  club_id uuid, callsign text, role text
) ON COMMIT DROP;
\copy _seed_members (club_id,callsign,role) FROM '$MEMBERS_CSV' WITH CSV
INSERT INTO club_members (club_id,callsign,role)
  SELECT club_id,callsign,role FROM _seed_members
  ON CONFLICT (club_id,callsign) DO NOTHING;

COMMIT;
SQL

# 3. Report what staging now holds.
"${PSQL[@]}" -d "$STAGING_DB" -c "SELECT (SELECT count(*) FROM clubs) AS clubs, (SELECT count(*) FROM club_members) AS members, (SELECT count(*) FROM club_members WHERE callsign='$CALL') AS operator_clubs;"

echo "Seeded staging clubs for $CALL."
