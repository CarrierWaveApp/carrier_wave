# Models Index

Data structures for database rows, API requests, and API responses.

## Files

### `src/models/mod.rs`
Module declarations and re-exports for all models.

**Exports:**
- Re-exports all public items from submodules

### `src/models/challenge.rs`
Challenge-related data structures.

**Exports:**
- `struct Challenge` - Database row for challenges table (FromRow)
- `struct ChallengeResponse` - API response for single challenge (Serialize)
- `struct ChallengeListItem` - API response for challenge in list (FromRow, Serialize)
- `struct CreateChallengeRequest` - API request for creating/updating challenge (Deserialize)
- `struct ListChallengesQuery` - Query params for listing challenges (Deserialize)
- `impl From<Challenge> for ChallengeResponse` - Conversion for API response

### `src/models/contest_definition.rs`
Contest definition row + response types for the `contest_definitions` table.
The full format types live in `src/contest/types.rs`.

**Exports:**
- `struct ContestDefinitionRow` - Database row (FromRow)
- `struct ContestDefinitionResponse` - API response for a single contest definition (camelCase)
- `struct ContestDefinitionListItem` - Compact list item (camelCase)
- `struct ListContestsQuery` - Query params (`includeInactive`)
- `struct ValidateContestsRequest` - Body for the validate-only admin endpoint
- `struct ValidationProblem` - Single validation problem in API responses (camelCase)
- `struct ValidateContestsResponse` - `{ valid, problems, contestCount }`
- `impl From<ContestDefinitionRow> for ContestDefinitionResponse` / `ContestDefinitionListItem`

### `src/models/participant.rs`
Participant and participation data structures.

**Exports:**
- `struct Participant` - Database row for participants table (FromRow)
- `struct ChallengeParticipant` - Database row for challenge_participants table (FromRow)
- `struct JoinChallengeRequest` - API request for joining challenge (Deserialize)
- `struct JoinChallengeResponse` - API response after joining (Serialize)
- `struct ParticipationResponse` - API response for participation status (Serialize)
- `struct ChallengeParticipation` - API response for challenge participation with name (FromRow, Serialize)

### `src/models/progress.rs`
Progress and leaderboard data structures.

**Exports:**
- `struct Progress` - Database row for progress table (FromRow)
- `struct ReportProgressRequest` - API request for reporting progress (Deserialize)
- `struct ProgressResponse` - API response for progress data (Serialize)
- `struct ReportProgressResponse` - API response after reporting progress (Serialize)
- `struct LeaderboardEntry` - Single leaderboard row (FromRow, Serialize)
- `struct LeaderboardResponse` - Full leaderboard response (Serialize)
- `struct LeaderboardQuery` - Query params for leaderboard (Deserialize)

### `src/models/badge.rs`
Badge data structures.

**Exports:**
- `struct Badge` - Database row with image data (FromRow)
- `struct BadgeMetadata` - Database row without image data (FromRow)
- `struct BadgeResponse` - API response for badge (Serialize)
- `struct CreateBadgeFields` - Multipart form fields for badge creation (Deserialize)
- `impl BadgeMetadata::into_response()` - Convert to API response with URL

### `src/models/invite.rs`
Invite token data structures.

**Exports:**
- `struct InviteToken` - Database row for invite_tokens table (FromRow)
- `struct InviteResponse` - API response for invite (Serialize)
- `struct CreateInviteRequest` - API request for creating invite (Deserialize)
- `impl InviteToken::into_response()` - Convert to API response with URL

### `src/models/user.rs`
User data structures.

**Exports:**
- `struct User` - Database row for users table (FromRow)
- `struct UserResponse` - API response for user (Serialize)
- `impl From<User> for UserResponse` - Conversion for API response

### `src/models/friend_request.rs`
Friend request data structures.

**Exports:**
- `struct FriendRequest` - Database row for friend_requests table (FromRow)
- `struct FriendRequestWithCallsigns` - Database row with joined callsigns (FromRow)
- `struct FriendRequestResponse` - API response for friend request (Serialize)
- `struct CreateFriendRequestBody` - API request body with to_user_id or invite_token (Deserialize)
- `struct Friendship` - Database row for friendships table (FromRow)
- `impl From<FriendRequestWithCallsigns> for FriendRequestResponse` - Conversion for API response

### `src/models/program.rs`
Activity program registry data structures.

**Exports:**
- `struct ProgramRow` - Database row for programs table (FromRow)
- `struct ProgramResponse` - API response for single program (Serialize, camelCase)
- `struct AdifFieldMapping` - ADIF field mapping nested object (Serialize)
- `struct DataEntryConfig` - Data entry config nested object (Serialize)
- `struct ProgramListResponse` - API response for program list with version (Serialize)
- `impl From<ProgramRow> for ProgramResponse` - Conversion with ADIF/data-entry flattening

### `src/models/friend_invite.rs`
Friend invite link data structures.

**Exports:**
- `struct FriendInvite` - Database row for friend_invites table (FromRow)
- `struct FriendInviteResponse` - API response for friend invite (Serialize)
- `impl FriendInvite::into_response()` - Convert to API response with URL

### `src/models/upload_error_telemetry.rs`
Upload error telemetry data structures.

**Exports:**
- `struct UploadErrorEntry` - Single error entry in a telemetry report (Deserialize)
- `struct ReportUploadErrorsRequest` - API request for reporting upload errors (Deserialize)
- `struct ReportUploadErrorsResponse` - API response for telemetry endpoint (Serialize)
- `struct TelemetryQuery` - Query params for admin telemetry summary (Deserialize)
- `struct ServiceCount` - Error count by service (FromRow, Serialize)
- `struct CategoryCount` - Error count by category (FromRow, Serialize)
- `struct DailyErrorCount` - Errors per day for trend chart (FromRow, Serialize)
- `struct RecentError` - Single recent error row (FromRow, Serialize)
- `struct TelemetrySummaryResponse` - Full admin telemetry response (Serialize)

### `src/models/spot_marker.rs`
Spot marker and Twilio webhook data structures.

**Exports:**
- `struct SpotMarkerRow` - Database row for spot_markers table (FromRow)
- `struct SpotMarkerResponse` - API response for spot marker (Serialize, camelCase)
- `struct TwilioSmsWebhook` - Twilio SMS webhook form fields (Deserialize)
- `enum SpotType` - Pota or Sota, determined by reference format
- `struct ParsedSpotMessage` - Parsed SMS spot message fields

### `src/models/equipment.rs`
Equipment catalog data structures.

**Exports:**
- `enum EquipmentCategory` - radio, antenna, key, microphone, accessory
- `enum Portability` - pocket, backpack, portable, mobile, base
- `struct EquipmentRow` - Database row for equipment_catalog table (FromRow)
- `struct EquipmentEntryResponse` - API response for single entry (Serialize)
- `struct CatalogResponse` - Full catalog response with version and entries
- `struct SearchResultEntry` - Search result with confidence and matched_field
- `struct SearchResponse` - Search results wrapper
- `struct EquipmentSearchRow` - DB row with score and matched_field (FromRow)
- `struct CatalogQuery` - Query params for catalog endpoint (since)
- `struct SearchQuery` - Query params for search endpoint (q, category, limit)
- `struct CreateEquipmentRequest` - Admin create request (Deserialize)
- `struct UpdateEquipmentRequest` - Admin partial update request (Deserialize)

### `src/models/event.rs`
Event data structures for user-submitted events.

**Exports:**
- `struct EventDayRow` - Database row for event_days table (FromRow)
- `struct EventDayResponse` - API response for a single event day (Serialize, Deserialize, camelCase)
- `struct EventDayRequest` - Request body for a single event day (Deserialize, camelCase)
- `struct EventRow` - Database row for events table (FromRow)
- `struct EventResponse` - API response for single event with optional days array (Serialize, camelCase)
- `struct EventListItem` - List item with optional distance_meters (FromRow, Serialize, camelCase)
- `struct CreateEventRequest` - API request for creating event with optional days (Deserialize, camelCase)
- `struct UpdateEventRequest` - API request for updating event with optional days, all fields optional (Deserialize, camelCase)
- `struct ReviewEventRequest` - API request for admin review with action + reason (Deserialize, camelCase)
- `struct ListEventsQuery` - Query params for proximity search (Deserialize, camelCase)
- `struct AdminListEventsQuery` - Query params for admin list (Deserialize, camelCase)
- `struct MyEventsQuery` - Query params for own events (Deserialize, camelCase)
- `struct SubmitterStats` - Submitter history stats (FromRow, Serialize, camelCase)
- `impl From<EventRow> for EventResponse` - Conversion for API response (days defaults to None)
- `impl EventResponse::with_days()` - Attach event days to response
