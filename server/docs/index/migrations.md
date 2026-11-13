# Migrations Index

SQL migrations for database schema and seed data.

## Files

### `migrations/001_initial_schema.sql`
Initial database schema with all tables and indexes.

**Tables:**
- `challenges` - Challenge definitions with configuration JSON
  - Columns: id, version, name, description, author, category, challenge_type, configuration, invite_config, hamalert_config, is_active, created_at, updated_at
  - Constraints: category IN (award, event, club, personal, other), challenge_type IN (collection, cumulative, timeBounded)

- `participants` - User accounts with device tokens
  - Columns: id, callsign, device_token, device_name, created_at, last_seen_at
  - Indexes: callsign, device_token (unique)

- `challenge_participants` - Many-to-many join table for challenge participation
  - Columns: id, challenge_id, callsign, invite_token, joined_at, status
  - Constraints: status IN (active, left, completed), UNIQUE(challenge_id, callsign)
  - Indexes: challenge_id, callsign

- `progress` - Progress tracking per user per challenge
  - Columns: id, challenge_id, callsign, completed_goals, current_value, score, current_tier, last_qso_date, updated_at
  - Constraints: UNIQUE(challenge_id, callsign)
  - Indexes: (challenge_id, score DESC, updated_at ASC) for leaderboard queries

- `badges` - Badge images stored as binary
  - Columns: id, challenge_id, name, tier_id, image_data, content_type, created_at
  - Indexes: challenge_id

- `earned_badges` - Track which badges users have earned
  - Columns: id, badge_id, callsign, earned_at
  - Constraints: UNIQUE(badge_id, callsign)
  - Indexes: callsign

- `challenge_snapshots` - Frozen leaderboards when challenges end
  - Columns: id, challenge_id, ended_at, final_standings, statistics, created_at
  - Indexes: challenge_id

- `invite_tokens` - Invite codes for private challenges
  - Columns: token (PK), challenge_id, max_uses, use_count, expires_at, created_at
  - Indexes: challenge_id

### `migrations/002_seed_challenges.sql`
Seed data for initial challenges.

**Challenges:**
- `ARRL WAS 250` (id: a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d)
  - Work all 50 US states during 2026
  - Type: collection, Category: award
  - No historical QSOs allowed
  - Time-bounded: 2026-01-01 to 2026-12-31

- `DXCC` (id: b2c3d4e5-f6a7-5b6c-9d0e-1f2a3b4c5d6e)
  - Work 100+ DXCC entities
  - Type: collection, Category: award
  - Historical QSOs allowed
  - Tiers: 50, 100 (DXCC), 150, 200, 250, 300, 331 (Honor Roll)

### `migrations/003_friend_system.sql`
Friend system: users, friend requests, and friend invite links.

**Tables:**
- `users` - Canonical user identity by callsign
  - Columns: id (UUID), callsign (TEXT UNIQUE), created_at
  - Populated from existing participants on migration
  - Indexes: callsign

- `friend_requests` - Friend requests between users
  - Columns: id, from_user_id, to_user_id, status, requested_at, responded_at
  - Constraints: status IN (pending, accepted, declined), UNIQUE(from_user_id, to_user_id)
  - Indexes: from_user_id, to_user_id, status (pending only)

- `friendships` - Bidirectional friendship records
  - Columns: id, user_id, friend_id, created_at
  - Constraints: UNIQUE(user_id, friend_id)
  - Indexes: user_id, friend_id

- `friend_invites` - Friend invite links
  - Columns: id, token, user_id, created_at, expires_at, used_at, used_by_user_id
  - Constraints: token format check (inv_ prefix + 20+ alphanumeric)
  - Indexes: token (unique), user_id, expires_at

### `migrations/004_seed_friends.sql`
Seed data for testing friend system features.

**Test Users:**
- `W1TEST` (id: 550e8400-e29b-41d4-a716-446655440001) - Primary test user
- `W6JSV` (id: 550e8400-e29b-41d4-a716-446655440002) - Friend of W1TEST
- `N3SEED` (id: 550e8400-e29b-41d4-a716-446655440003) - Has pending request to W1TEST
- `AA4DEV` (id: 550e8400-e29b-41d4-a716-446655440004) - Stranger (no relationships)

**Relationships:**
- Friendship: W1TEST ↔ W6JSV
- Pending request: N3SEED → W1TEST
- Active invite: W1TEST's `inv_w1testactiveinvite12345`
- Used invite: `inv_usedinvitetoken1234567` (used by W6JSV)

### `migrations/006_programs.sql`
Activity program registry table and seed data.

**Tables:**
- `programs` - Activity program definitions
  - Columns: slug (PK), name, short_name, icon, icon_url, website, server_base_url, reference_label, reference_format, reference_example, multi_ref_allowed, activation_threshold, supports_rove, capabilities (TEXT[]), adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field, data_entry_label, data_entry_placeholder, data_entry_format, sort_order, is_active, created_at, updated_at

**Seed Programs:**
- `casual` (sort 0) - No capabilities
- `pota` (sort 1) - Parks on the Air, full feature set
- `sota` (sort 2) - Summits on the Air, reference + ADIF
- `wwff` (sort 3) - World Wide Flora & Fauna, reference + ADIF
- `iota` (sort 4) - Islands on the Air, reference only
- `lota` (sort 5) - Lighthouses on the Air, reference only
- `aoa` (sort 6) - Agents on Air, reference + hunter + dataEntry + dataVerification

### `migrations/013_reset_park_boundaries.sql`
Truncates park_boundaries cache to force refetch with multi-parcel merge fix.

**Operations:**
- `TRUNCATE TABLE park_boundaries` - Clears all cached boundaries so the aggregator refetches with merged geometry

### `migrations/014_pota_fetch_consecutive_errors.sql`
Adds consecutive error counter to pota_fetch_status.

**Columns added:**
- `consecutive_errors` (INTEGER NOT NULL DEFAULT 0) - Tracks consecutive fetch failures; parks with 3+ errors are skipped until the next catalog re-sync resets counters

### `migrations/015_trail_fetch_consecutive_errors.sql`
Adds consecutive error counter to historic_trail_catalog.

**Columns added:**
- `consecutive_errors` (INTEGER NOT NULL DEFAULT 0) - Tracks consecutive fetch failures; trails with 3+ errors are skipped until counters reset at the start of each cycle

### `migrations/016_add_anza_trail.sql`
Adds Juan Bautista de Anza National Historic Trail to the catalog.

**Data:**
- Inserts NHT-ANZA into historic_trail_catalog (NPS, AZ/CA)

### `migrations/017_ntir_trail_sources.sql`
Adds NTIR (NPS National Trails Intermountain Region) Feature Service names as a secondary data source for trails not in the USGS National Map.

**Columns added:**
- `ntir_service` (TEXT) on historic_trail_catalog - NTIR Feature Service name for per-trail ArcGIS endpoint

**Data:**
- Maps 18 existing catalog trails to their NTIR Feature Service names
- Inserts NHT-BTFD (Butterfield Overland National Historic Trail) with NTIR source

### `migrations/018_reset_exact_match_boundaries.sql`
Forces re-fetch of US park boundaries matched by name after fixing over-broad LIKE query.

**Operations:**
- Sets `fetched_at` to epoch for all `match_quality = 'exact'` / `source = 'pad_us_4'` rows, triggering stale-boundary refresh with the new exact-match-first query logic

### `migrations/019_events.sql`
User-submitted events with admin moderation and proximity-based discovery.

**Tables:**
- `events` - User-submitted event definitions with location
  - Columns: id (UUID), name, description, event_type, start_date, end_date, timezone, venue_name, address, city, state, country, latitude, longitude, location (geography Point), cost, url, submitted_by, status, reviewed_by, reviewed_at, rejection_reason, created_at, updated_at
  - Constraints: event_type IN (club_meeting, swap_meet, field_day, special_event, hamfest, net, other), status IN (pending, approved, rejected), length checks on name/description/venue_name/cost
  - Indexes: GIST on location (proximity), (status, start_date), submitted_by

**Functions/Triggers:**
- `events_set_location()` - Trigger function that auto-populates the geography column from lat/lon on insert or update

### `migrations/020_event_days.sql`
Per-day scheduling for multi-day events.

**Tables:**
- `event_days` - Individual day entries for multi-day events
  - Columns: id (UUID), event_id (UUID FK → events ON DELETE CASCADE), date (DATE), start_time (TIMESTAMPTZ), end_time (TIMESTAMPTZ), created_at
  - Indexes: (event_id, date)

### `migrations/021_upload_error_telemetry.sql`
Anonymized upload error telemetry from client apps.

**Tables:**
- `upload_error_telemetry` - Aggregated error reports from client sync
  - Columns: id (UUID), callsign (TEXT), service (TEXT), category (TEXT), message_hash (TEXT), affected_count (INTEGER), is_transient (BOOLEAN), app_version (TEXT), os_version (TEXT), created_at (TIMESTAMPTZ)
  - Indexes: created_at, (service, created_at), (category, created_at)

### `migrations/024_club_logos.sql`
Add logo storage columns to clubs table.

**Columns added:**
- `logo_data` (BYTEA) - Logo image binary data
- `logo_content_type` (TEXT) - MIME type of the logo image

### `migrations/026_callsign_history.sql`
Callsign change audit log.

**Tables:**
- `callsign_history` - Records callsign changes with user_id, old_callsign, new_callsign, changed_at

**Indexes:**
- `idx_callsign_history_user_id` - Lookup history by user
- `idx_callsign_history_old` - Lookup by previous callsign

### `migrations/027_equipment_catalog.sql`
Equipment catalog schema with pg_trgm fuzzy search support.

**Extensions:**
- `pg_trgm` - Trigram similarity for fuzzy text matching

**Tables:**
- `equipment_catalog` - Amateur radio equipment entries
  - Columns: id (TEXT PK slug), name, manufacturer, category, bands, modes, max_power_watts, portability, weight_grams, description, aliases, image_url, created_at, updated_at
  - Constraints: category IN (radio, antenna, key, microphone, accessory), portability IN (pocket, backpack, portable, mobile, base)

**Indexes:**
- `idx_equipment_catalog_trgm` - GIN trigram index on name + aliases for fuzzy search
- `idx_equipment_catalog_category` - Category filter
- `idx_equipment_catalog_updated_at` - Delta sync queries

### `migrations/028_equipment_seed_data.sql`
Seed data for equipment catalog with POTA/portable-popular gear.

Includes radios (Elecraft, Icom, Yaesu, LNR, QRP Labs, Xiegu, Lab599), antennas (EFHW, Spooltenna, Chameleon, Buddipole, SOTAbeams, PackTenna, Wolf River, Super Antenna), keys (CW Morse, Begali, Vibroplex, N0SA, Palm, AME), microphones (Heil Sound), and accessories (Bioenno batteries, masts).

### `migrations/032_contest_definitions.sql`
Storage for v0.3 contest definitions. Each contest within a definition file
becomes its own row keyed by `contest.id`.

**Tables:**
- `contest_definitions`
  - Columns: id (TEXT PK), name, short_name, sponsor_name, sponsor_url, format_version, definition (JSONB), is_active, created_at, updated_at

**Indexes:**
- `idx_contest_definitions_active` - Active filter + name ordering for list endpoint
