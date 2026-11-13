# Handlers Index

HTTP request handlers for all API endpoints.

## Files

### `src/handlers/mod.rs`
Module declarations and re-exports for all handlers.

**Exports:**
- Re-exports all public items from submodules

### `src/handlers/challenges.rs`
Challenge CRUD operations and listing.

**Exports:**
- `struct DataResponse<T>` - Generic wrapper for JSON responses with `data` field
- `struct ListChallengesResponse` - Paginated challenge list response
- `async fn list_challenges()` - GET /v1/challenges - List challenges with filtering
- `async fn get_challenge()` - GET /v1/challenges/:id - Get challenge details with ETag
- `async fn create_challenge()` - POST /v1/admin/challenges - Create new challenge (admin)
- `async fn update_challenge()` - PUT /v1/admin/challenges/:id - Update challenge (admin)
- `async fn delete_challenge()` - DELETE /v1/admin/challenges/:id - Delete challenge (admin)

### `src/handlers/contests.rs`
Contest definition CRUD, listing, and validation. See the loader/validator
in [docs/index/contest.md](contest.md) and the format reference in
[docs/features/contest-definitions.md](../features/contest-definitions.md).

**Exports:**
- `struct ListContestsResponse` - Wrapper around `Vec<ContestDefinitionListItem>`
- `struct UpsertContestsResponse` - Wrapper for the upsert response with `contests` and `warnings`
- `async fn list_contests()` - GET /v1/contests - List active contest definitions (?includeInactive=true)
- `async fn get_contest()` - GET /v1/contests/:id - Get full contest definition
- `async fn upsert_contests()` - POST /v1/admin/contests - Upsert all contests in a definition file (validates first; rejects on errors)
- `async fn delete_contest()` - DELETE /v1/admin/contests/:id - Hard-delete a contest definition
- `async fn validate_contests()` - POST /v1/admin/contests/validate - Validate without persisting

### `src/handlers/join.rs`
Challenge participation management.

**Exports:**
- `async fn join_challenge()` - POST /v1/challenges/:id/join - Join a challenge
- `async fn leave_challenge()` - DELETE /v1/challenges/:id/leave - Leave a challenge (auth required)

### `src/handlers/progress.rs`
Progress reporting and score calculation.

**Exports:**
- `async fn report_progress()` - POST /v1/challenges/:id/progress - Report progress (auth required)
- `async fn get_progress()` - GET /v1/challenges/:id/progress - Get own progress (auth required)
- `fn calculate_score()` - Calculate score based on challenge config
- `fn calculate_percentage()` - Calculate completion percentage
- `fn calculate_percentage_from_progress()` - Calculate percentage from stored progress
- `fn get_total_goals()` - Get total goal count from config
- `fn determine_tier()` - Determine current tier based on score

### `src/handlers/leaderboard.rs`
Leaderboard queries.

**Exports:**
- `async fn get_leaderboard()` - GET /v1/challenges/:id/leaderboard - Get leaderboard with pagination

### `src/handlers/participants.rs`
Participant queries with callsign-based authorization.

**Exports:**
- `async fn get_participation_status()` - GET /v1/challenges/:id/participants/:callsign - Get participation status (auth required, callsign must match)
- `async fn list_challenges_for_callsign()` - GET /v1/participants/:callsign/challenges - List all challenges for a callsign (auth required, callsign must match)

### `src/handlers/health.rs`
Health check endpoint.

**Exports:**
- `struct HealthResponse` - Health check response with status and version
- `async fn health_check()` - GET /v1/health - Return server health status

### `src/handlers/badges.rs`
Badge upload, listing, and retrieval.

**Exports:**
- `struct BadgeListResponse` - List of badges for a challenge
- `async fn upload_badge()` - POST /v1/admin/challenges/:id/badges - Upload badge image (admin)
- `async fn list_badges()` - GET /v1/admin/challenges/:id/badges - List badges (admin)
- `async fn get_badge_image()` - GET /v1/badges/:id/image - Get badge image data
- `async fn delete_badge()` - DELETE /v1/admin/badges/:id - Delete badge (admin)

### `src/handlers/invites.rs`
Invite token management.

**Exports:**
- `struct InviteListResponse` - List of invites for a challenge
- `async fn generate_invite()` - POST /v1/admin/challenges/:id/invites - Generate invite token (admin)
- `async fn list_invites()` - GET /v1/admin/challenges/:id/invites - List invites (admin)
- `async fn revoke_invite()` - DELETE /v1/admin/invites/:token - Revoke invite token (admin)

### `src/handlers/programs.rs`
Activity program registry endpoints (public, no auth).

**Exports:**
- `async fn list_programs()` - GET /v1/programs - List all active programs with version
- `async fn get_program()` - GET /v1/programs/:slug - Get single program by slug

- `async fn delete_activity()` - DELETE /v1/activities/:id - Delete own activity (auth required)

### `src/handlers/invite_page.rs`
Server-rendered HTML page for friend invite links opened in browsers.

**Exports:**
- `async fn invite_page()` - GET /invite/:token - Render HTML page with inviter callsign and deep link to Carrier Wave

### `src/handlers/rbn.rs`
RBN (Reverse Beacon Network) proxy endpoints. Serves spots from in-memory store fed by telnet ingester.

**Exports:**
- `async fn rbn_spots()` - GET /v1/rbn/spots - Query spots with filters (call, spotter, mode, band, freq range, since, limit)
- `async fn rbn_stats()` - GET /v1/rbn/stats - Aggregate statistics (total, per-minute rate, band/mode breakdown)
- `async fn rbn_skimmers()` - GET /v1/rbn/skimmers - Active skimmers with spot counts and bands

### `src/handlers/websdr.rs`
KiwiSDR proxies for the logbook viewer's Spots page. All targets SSRF-validated (host syntax, port allowlist, DNS must resolve to public unicast only).

**Exports:**
- `WebSdrState` - Shared reqwest client + in-memory directory cache (Extension)
- `async fn websdr_directory()` - GET /v1/websdr/directory - Skywavelinux kiwisdr_com.js, cached ~1h, returned as raw JS text
- `async fn websdr_status()` - GET /v1/websdr/status?host=&port= - Proxy one receiver /status fetch (5s timeout)
- `async fn websdr_stream()` - GET /v1/websdr/stream?host=&port= - Transparent WebSocket byte bridge to ws://host:port/{unix_ts}/SND

### `src/handlers/friends.rs`
Friend invite links and friend requests.

**Exports:**
- `async fn get_invite_link()` - GET /v1/friends/invite-link - Generate friend invite link (auth required)
- `async fn create_friend_request()` - POST /v1/friends/requests - Create friend request by user ID or invite token (auth required)

### `src/handlers/clubs.rs`
Authenticated club endpoints for members.

**Exports:**
- `async fn get_clubs()` - GET /v1/clubs - Get clubs for the authenticated user
- `async fn sync_clubs()` - GET /v1/clubs/sync - Batch-fetch all clubs with full member details and ETag support (optimized for app startup)
- `async fn get_club_details()` - GET /v1/clubs/:id - Get club details with members (requires membership)
- `async fn get_club_activity()` - GET /v1/clubs/:id/activity - Get club activity feed (requires membership)
- `async fn get_club_status()` - GET /v1/clubs/:id/status - Get real-time member online status (requires membership)
- `async fn update_club_notes()` - PUT /v1/clubs/:id/notes - Update club notes (requires club admin role)
- `async fn get_club_logo()` - GET /v1/clubs/:id/logo - Serve club logo image (public, no auth)

### `src/handlers/clubs_admin.rs`
Admin CRUD for clubs and members.

**Exports:**
- `async fn list_clubs_admin()` - GET /v1/admin/clubs - List all clubs with member counts
- `async fn list_club_members_admin()` - GET /v1/admin/clubs/:id/members - List club members
- `async fn create_club()` - POST /v1/admin/clubs - Create a club
- `async fn update_club()` - PUT /v1/admin/clubs/:id - Update club metadata
- `async fn delete_club()` - DELETE /v1/admin/clubs/:id - Delete a club
- `async fn add_club_members()` - POST /v1/admin/clubs/:id/members - Add members
- `async fn remove_club_member()` - DELETE /v1/admin/clubs/:id/members/:callsign - Remove member
- `async fn update_club_member_role()` - PUT /v1/admin/clubs/:id/members/:callsign - Update role
- `async fn import_notes_members()` - POST /v1/admin/clubs/:id/import-notes - Import members from callsign notes URL
- `async fn upload_club_logo()` - PUT /v1/admin/clubs/:id/logo - Upload or replace club logo
- `async fn delete_club_logo()` - DELETE /v1/admin/clubs/:id/logo - Remove club logo

### `src/handlers/equipment.rs`
Equipment catalog endpoints (public + admin).

**Exports:**
- `async fn get_catalog()` - GET /v1/equipment/catalog - Full catalog with ETag and optional `since` delta
- `async fn search_equipment()` - GET /v1/equipment/search - Fuzzy search with pg_trgm
- `async fn create_equipment()` - POST /v1/admin/equipment - Create equipment entry (admin)
- `async fn update_equipment()` - PUT /v1/admin/equipment/:id - Update equipment entry (admin)
- `async fn delete_equipment()` - DELETE /v1/admin/equipment/:id - Delete equipment entry (admin)

### `src/handlers/events.rs`
Public and authenticated event endpoints.

**Exports:**
- `async fn list_events()` - GET /v1/events - List approved events near a location (proximity search)
- `async fn get_event()` - GET /v1/events/:id - Get single approved event
- `async fn create_event()` - POST /v1/events - Submit a new event (auth required, status=pending)
- `async fn update_event()` - PUT /v1/events/:id - Edit own event (auth required, key-field edits reset approval)
- `async fn delete_event()` - DELETE /v1/events/:id - Delete own event (auth required)
- `async fn list_my_events()` - GET /v1/events/mine - List own submitted events, all statuses (auth required)

### `src/handlers/upload_error_telemetry.rs`
Upload error telemetry reporting.

**Exports:**
- `async fn report_upload_errors()` - POST /v1/telemetry/upload-errors - Report anonymized upload error telemetry (auth required)
- `async fn get_telemetry_summary()` - GET /v1/admin/telemetry/upload-errors - Upload error telemetry summary (admin)

### `src/handlers/twilio_webhook.rs`
Twilio SMS webhook for POTA/SOTA spotting and marker generation.

**Exports:**
- `async fn create_spot_marker()` - POST /v1/spot-markers - Generate a spot marker for SMS spotting (auth required)
- `async fn twilio_sms_webhook()` - POST /v1/twilio/sms - Twilio webhook for incoming SMS spot messages (public, form-encoded)

### `src/handlers/events_admin.rs`
Admin event moderation endpoints.

**Exports:**
- `async fn list_events_admin()` - GET /v1/admin/events - List events with optional status filter
- `async fn admin_get_event()` - GET /v1/admin/events/:id - Get any event regardless of status
- `async fn admin_update_event()` - PUT /v1/admin/events/:id - Edit any event fields
- `async fn review_event()` - PUT /v1/admin/events/:id/review - Approve or reject an event
- `async fn admin_delete_event()` - DELETE /v1/admin/events/:id - Hard delete any event
- `async fn get_submitter_history()` - GET /v1/admin/events/submitter/:callsign - Get submitter stats

### `src/handlers/users.rs`
User management, search, registration, and account operations.

**Exports:**
- `async fn search_users()` - GET /v1/users/search?q=... - Search users by callsign (public)
- `async fn admin_stats()` - GET /v1/admin/stats - Aggregate user statistics (admin)
- `async fn admin_users_by_hour()` - GET /v1/admin/stats/users-by-hour - Active users per hour (admin)
- `async fn register()` - POST /v1/register - Register user and get auth token
- `async fn change_callsign()` - PUT /v1/account/callsign - Change callsign across all tables (auth required)
- `async fn delete_account()` - DELETE /v1/account - Delete account and all data (auth required)
