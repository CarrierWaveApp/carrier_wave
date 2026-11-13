# Database Index

Database query functions using sqlx with compile-time checked queries.

## Files

### `src/db/mod.rs`
Module declarations and re-exports for all database functions.

**Exports:**
- Re-exports all public items from submodules

### `src/db/challenges.rs`
Challenge CRUD queries.

**Exports:**
- `async fn list_challenges()` - List challenges with filtering, returns `(Vec<ChallengeListItem>, i64)`
- `async fn get_challenge()` - Get challenge by ID, returns `Option<Challenge>`
- `async fn create_challenge()` - Insert new challenge, returns `Challenge`
- `async fn update_challenge()` - Update challenge, increments version, returns `Option<Challenge>`
- `async fn delete_challenge()` - Delete challenge by ID, returns `bool`

### `src/db/contest_definitions.rs`
Contest definition CRUD against the `contest_definitions` table.

**Exports:**
- `async fn list()` - List contest definitions, optionally including inactive
- `async fn get()` - Get a single contest definition by id
- `async fn upsert_all()` - Transactionally upsert every contest in a `ContestDefinition` file
- `async fn delete()` - Hard-delete a contest definition by id

### `src/db/participants.rs`
Participant and challenge participation management.

**Exports:**
- `async fn get_or_create_participant()` - Get or create participant by callsign, returns `(Participant, bool)`
- `async fn get_participant_by_token()` - Lookup participant by device token, returns `Option<Participant>`
- `async fn join_challenge()` - Create challenge participation, returns `ChallengeParticipant`
- `async fn get_participation()` - Get participation record, returns `Option<ChallengeParticipant>`
- `async fn leave_challenge()` - Set participation status to 'left', returns `bool`
- `async fn revoke_tokens()` - Delete all participant records for callsign, returns `u64`
- `async fn refresh_participant_token()` - Generate and update device token for callsign, returns `Participant`
- `async fn get_challenges_for_callsign()` - Get all active challenge participations for callsign, returns `Vec<ChallengeParticipation>`

### `src/db/progress.rs`
Progress tracking and leaderboard queries.

**Exports:**
- `async fn get_progress()` - Get progress for callsign in challenge, returns `Option<Progress>`
- `async fn upsert_progress()` - Insert or update progress with score/tier, returns `Progress`
- `async fn get_rank()` - Get callsign's rank in challenge, returns `Option<i64>`
- `async fn get_leaderboard()` - Get paginated leaderboard, returns `(Vec<LeaderboardEntry>, i64)`
- `async fn get_leaderboard_around()` - Get leaderboard entries around a callsign, returns `Vec<LeaderboardEntry>`
- `impl From<serde_json::Error> for AppError` - Error conversion

### `src/db/badges.rs`
Badge storage and retrieval.

**Exports:**
- `async fn create_badge()` - Store badge with image data, returns `BadgeMetadata`
- `async fn list_badges()` - List badges for challenge (without image data), returns `Vec<BadgeMetadata>`
- `async fn get_badge()` - Get badge with image data, returns `Option<Badge>`
- `async fn delete_badge()` - Delete badge by ID, returns `bool`

### `src/db/invites.rs`
Invite token management.

**Exports:**
- `fn generate_invite_token()` - Generate random invite token with `inv_` prefix
- `async fn create_invite()` - Create invite token, returns `InviteToken`
- `async fn list_invites()` - List invites for challenge, returns `Vec<InviteToken>`
- `async fn get_invite()` - Get invite by token, returns `Option<InviteToken>`
- `async fn delete_invite()` - Delete invite by token, returns `bool`

### `src/db/users.rs`
User management.

**Exports:**
- `async fn get_user_by_callsign()` - Get user by callsign, returns `Option<User>`
- `async fn get_user_by_id()` - Get user by ID, returns `Option<User>`
- `async fn change_callsign()` - Change callsign across all tables in a transaction, returns `User`
- `async fn get_or_create_user()` - Get or create user by callsign, returns `User`

### `src/db/programs.rs`
Program registry queries.

**Exports:**
- `async fn list_programs()` - List active programs ordered by sort_order, returns `Vec<ProgramRow>`
- `async fn get_program()` - Get active program by slug, returns `Option<ProgramRow>`
- `async fn get_programs_version()` - Get max(updated_at) as epoch seconds, returns `i64`

### `src/db/activities.rs`
Activity CRUD queries.

**Exports:**
- `async fn insert_activity()` - Insert new activity, returns `Activity`
- `async fn delete_activity()` - Delete activity by ID with ownership check, returns `()`
- `async fn get_feed_for_user()` - Get activity feed from friends with cursor pagination, returns `Vec<FeedItemRow>`

### `src/db/friend_requests.rs`
Friend request management.

**Exports:**
- `async fn create_friend_request()` - Create friend request, returns `FriendRequestWithCallsigns`
- `async fn get_friend_request()` - Get request by ID, returns `Option<FriendRequest>`
- `async fn get_pending_request_between()` - Check for pending request between users, returns `Option<FriendRequest>`
- `async fn are_friends()` - Check if users are friends, returns `bool`
- `async fn accept_friend_request()` - Accept request and create friendships, returns `Option<FriendRequestWithCallsigns>`
- `async fn decline_friend_request()` - Decline request, returns `Option<FriendRequest>`

### `src/db/friend_invites.rs`
Friend invite link management.

**Exports:**
- `async fn create_friend_invite()` - Create friend invite, returns `FriendInvite`
- `async fn get_friend_invite()` - Get invite by token, returns `Option<FriendInvite>`
- `async fn get_valid_friend_invite()` - Get valid (not expired, not used) invite, returns `Option<FriendInvite>`
- `async fn mark_invite_used()` - Mark invite as used, returns `Option<FriendInvite>`
- `async fn cleanup_expired_invites()` - Delete old expired/used invites, returns `u64`

### `src/db/upload_error_telemetry.rs`
Upload error telemetry storage.

**Exports:**
- `async fn insert_upload_errors()` - Insert a batch of upload error telemetry entries, returns `usize`
- `async fn get_telemetry_summary()` - Get aggregated telemetry summary with filters, returns `TelemetrySummaryResponse`

### `src/db/spot_markers.rs`
Spot marker management for SMS-based spotting.

**Exports:**
- `fn generate_marker()` - Generate a random 6-character alphanumeric marker code
- `async fn create_spot_marker()` - Create a spot marker for a participant (replaces existing), returns `SpotMarkerRow`
- `async fn get_spot_marker()` - Look up a spot marker by code, returns `Option<SpotMarkerRow>`

### `src/db/equipment.rs`
Equipment catalog CRUD and fuzzy search queries.

**Exports:**
- `async fn get_catalog_version()` - Returns (count, latest updated_at) for catalog
- `async fn get_catalog_entries()` - List all entries, optionally filtered by `since` timestamp
- `async fn search_equipment()` - Fuzzy search via pg_trgm similarity
- `async fn get_entry()` - Get single entry by ID
- `async fn create_entry()` - Insert new equipment entry
- `async fn update_entry()` - Partial update of equipment entry
- `async fn delete_entry()` - Delete equipment entry by ID
- `async fn get_catalog_fingerprint()` - Compute ETag fingerprint from count + max updated_at

### `src/db/events.rs`
Event CRUD and proximity queries.

**Exports:**
- `async fn list_events_near()` - List approved events near a location with PostGIS proximity search, returns `(Vec<EventListItem>, i64)`
- `async fn get_event()` - Get event by ID, returns `Option<EventRow>`
- `async fn create_event()` - Create event with pending status, returns `EventRow`
- `async fn update_own_event()` - Update own event (key-field changes reset approval), returns `Option<EventRow>`
- `async fn delete_own_event()` - Delete own event, returns `bool`
- `async fn list_my_events()` - List events by callsign (all statuses), returns `Vec<EventListItem>`
- `async fn count_pending_events()` - Count pending events for a callsign, returns `i64`
- `async fn list_events_admin()` - Admin list with status filter, returns `(Vec<EventListItem>, i64)`
- `async fn admin_update_event()` - Admin update any event, returns `Option<EventRow>`
- `async fn review_event()` - Approve or reject an event, returns `Option<EventRow>`
- `async fn admin_delete_event()` - Hard delete any event, returns `bool`
- `async fn get_submitter_history()` - Get submitter stats, returns `SubmitterStats`
- `async fn get_event_days()` - Fetch days for a single event ordered by date, returns `Vec<EventDayRow>`
- `async fn get_event_days_batch()` - Fetch days for multiple events at once, returns `Vec<EventDayRow>`
- `async fn replace_event_days()` - Replace all days for an event (delete + insert), returns `Vec<EventDayRow>`

### `src/db/clubs.rs`
Club queries for admin and authenticated users.

**Exports:**
- `async fn create_club()` - Create a new club, returns `Club`
- `async fn update_club()` - Update club metadata (COALESCE for partial updates), returns `Option<Club>`
- `async fn update_club_notes()` - Set club notes URL and title, returns `Option<Club>`
- `async fn delete_club()` - Delete club by ID, returns `bool`
- `async fn add_members()` - Upsert members to a club (bumps `clubs.updated_at`), returns `Vec<ClubMember>`
- `async fn remove_member()` - Remove member from a club (bumps `clubs.updated_at`), returns `bool`
- `async fn update_member_role()` - Update a member's role (bumps `clubs.updated_at`), returns `bool`
- `async fn list_clubs_with_notes_url()` - Clubs the roster aggregator should sync, returns `Vec<Club>`
- `async fn reconcile_roster()` - Make a roster match a callsign list (add missing, drop departed `member` rows, keep admins, bump ETag), returns `RosterReconcile`
- `async fn record_roster_sync()` - Store `roster_synced_at` / `roster_sync_status` on the club
- `async fn list_all_clubs()` - List all clubs with member counts (admin), returns `Vec<ClubWithCount>`
- `async fn get_clubs_for_callsign()` - Get clubs for a callsign with member counts, returns `Vec<ClubWithCount>`
- `async fn get_club_detail()` - Get single club by ID, returns `Option<Club>`
- `async fn get_club_members_enriched()` - Get members with presence data, returns `Vec<EnrichedClubMember>`
- `async fn get_members_for_clubs()` - Batch-fetch members for multiple clubs (avoids N+1), returns `Vec<EnrichedClubMemberWithClub>`
- `async fn get_clubs_fingerprint()` - Compute ETag fingerprint for a user's clubs, returns `i64`
- `async fn get_club_activity()` - Get activities from club members with cursor pagination, returns `Vec<ActivityWithCallsign>`
- `async fn is_club_member()` - Check membership, returns `bool`
- `async fn get_club_logo()` - Get club logo data and content type, returns `Option<ClubLogo>`
- `async fn set_club_logo()` - Store or replace a club's logo, returns `bool`
- `async fn delete_club_logo()` - Remove a club's logo, returns `bool`
