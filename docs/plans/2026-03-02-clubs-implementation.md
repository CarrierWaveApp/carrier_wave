# Clubs Feature Implementation Plan (CAR-108)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add club support so ham radio clubs can see members' activity, online status, and proximity — surfaced throughout the app (club hub, logger, QSO detail, spots, map).

**Architecture:** Thin server (Rust/Axum + PostgreSQL) provides club CRUD and member management via admin endpoints, plus authenticated endpoints for club list/detail/activity/status. iOS app (SwiftUI/SwiftData) caches club data locally for offline access, with in-memory callsign sets for O(1) logger lookups.

**Tech Stack:** Rust (Axum, SQLx, PostgreSQL) for server; Swift (SwiftUI, SwiftData) for iOS.

**Design doc:** `docs/plans/2026-03-02-clubs-design.md`

---

## Phase 1: Server — Data Model & Migration

### Task 1: Database migration for clubs and club_members

**Files:**
- Create: `~/projects/activities-server/migrations/008_clubs.sql`

**Step 1: Write the migration**

```sql
-- Club entities
CREATE TABLE clubs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL,
    callsign        TEXT,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Club membership (admin-managed roster)
CREATE TABLE club_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id         UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(club_id, callsign)
);

CREATE INDEX idx_club_members_callsign ON club_members(callsign);
CREATE INDEX idx_club_members_club_id ON club_members(club_id);
```

**Step 2: Run the migration**

Run: `cd ~/projects/activities-server && sqlx migrate run`
Expected: Migration 008 applied successfully.

**Step 3: Commit**

```bash
git add migrations/008_clubs.sql
git commit -m "feat: add clubs and club_members tables (CAR-108)"
```

---

### Task 2: Rust models for clubs

**Files:**
- Create: `~/projects/activities-server/src/models/club.rs`
- Modify: `~/projects/activities-server/src/models/mod.rs`

**Step 1: Create the club model**

Follow the pattern in `models/user.rs` — separate `FromRow` (DB) and `Serialize` (API) types:

```rust
// models/club.rs

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

// --- Database types ---

#[derive(Debug, Clone, FromRow)]
pub struct Club {
    pub id: Uuid,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, FromRow)]
pub struct ClubMember {
    pub id: Uuid,
    pub club_id: Uuid,
    pub callsign: String,
    pub role: String,
    pub joined_at: DateTime<Utc>,
}

// --- API response types ---

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubResponse {
    pub id: Uuid,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    pub member_count: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubDetailResponse {
    pub id: Uuid,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    pub members: Vec<ClubMemberResponse>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubMemberResponse {
    pub callsign: String,
    pub role: String,
    pub joined_at: DateTime<Utc>,
    pub last_seen_at: Option<DateTime<Utc>>,
    pub last_grid: Option<String>,
    pub is_carrier_wave_user: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MemberStatusResponse {
    pub callsign: String,
    pub status: MemberOnlineStatus,
    pub spot_info: Option<SpotInfo>,
    pub last_seen_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum MemberOnlineStatus {
    OnAir,
    RecentlyActive,
    Inactive,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotInfo {
    pub frequency: f64,
    pub mode: Option<String>,
    pub source: String,
    pub spotted_at: DateTime<Utc>,
}

// --- API request types ---

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateClubRequest {
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateClubRequest {
    pub name: Option<String>,
    pub callsign: Option<String>,
    pub description: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddMembersRequest {
    pub members: Vec<AddMemberEntry>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddMemberEntry {
    pub callsign: String,
    pub role: Option<String>, // defaults to "member"
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateMemberRoleRequest {
    pub role: String,
}
```

**Step 2: Export from mod.rs**

Add to `models/mod.rs`:
```rust
pub mod club;
pub use club::*;
```

**Step 3: Build to verify**

Run: `cargo build`
Expected: Compiles with no errors.

**Step 4: Commit**

```bash
git add src/models/club.rs src/models/mod.rs
git commit -m "feat: add club model types (CAR-108)"
```

---

### Task 3: Database queries for clubs

**Files:**
- Create: `~/projects/activities-server/src/db/clubs.rs`
- Modify: `~/projects/activities-server/src/db/mod.rs`

**Step 1: Create the clubs DB module**

Follow the pattern in `db/friend_requests.rs`:

```rust
// db/clubs.rs

use sqlx::PgPool;
use uuid::Uuid;
use crate::models::{Club, ClubMember, ClubMemberResponse, ClubResponse};

// --- Admin operations ---

pub async fn create_club(pool: &PgPool, name: &str, callsign: Option<&str>, description: Option<&str>) -> Result<Club, sqlx::Error> {
    sqlx::query_as::<_, Club>(
        "INSERT INTO clubs (name, callsign, description) VALUES ($1, $2, $3) RETURNING *"
    )
    .bind(name)
    .bind(callsign)
    .bind(description)
    .fetch_one(pool)
    .await
}

pub async fn update_club(pool: &PgPool, club_id: Uuid, name: Option<&str>, callsign: Option<&str>, description: Option<&str>) -> Result<Option<Club>, sqlx::Error> {
    sqlx::query_as::<_, Club>(
        "UPDATE clubs SET
            name = COALESCE($2, name),
            callsign = COALESCE($3, callsign),
            description = COALESCE($4, description),
            updated_at = now()
         WHERE id = $1
         RETURNING *"
    )
    .bind(club_id)
    .bind(name)
    .bind(callsign)
    .bind(description)
    .fetch_optional(pool)
    .await
}

pub async fn delete_club(pool: &PgPool, club_id: Uuid) -> Result<bool, sqlx::Error> {
    let result = sqlx::query("DELETE FROM clubs WHERE id = $1")
        .bind(club_id)
        .execute(pool)
        .await?;
    Ok(result.rows_affected() > 0)
}

pub async fn add_members(pool: &PgPool, club_id: Uuid, members: &[(String, String)]) -> Result<Vec<ClubMember>, sqlx::Error> {
    let mut results = Vec::new();
    for (callsign, role) in members {
        let member = sqlx::query_as::<_, ClubMember>(
            "INSERT INTO club_members (club_id, callsign, role)
             VALUES ($1, $2, $3)
             ON CONFLICT (club_id, callsign) DO UPDATE SET role = $3
             RETURNING *"
        )
        .bind(club_id)
        .bind(callsign)
        .bind(role)
        .fetch_one(pool)
        .await?;
        results.push(member);
    }
    Ok(results)
}

pub async fn remove_member(pool: &PgPool, club_id: Uuid, callsign: &str) -> Result<bool, sqlx::Error> {
    let result = sqlx::query("DELETE FROM club_members WHERE club_id = $1 AND callsign = $2")
        .bind(club_id)
        .bind(callsign)
        .execute(pool)
        .await?;
    Ok(result.rows_affected() > 0)
}

pub async fn update_member_role(pool: &PgPool, club_id: Uuid, callsign: &str, role: &str) -> Result<bool, sqlx::Error> {
    let result = sqlx::query("UPDATE club_members SET role = $3 WHERE club_id = $1 AND callsign = $2")
        .bind(club_id)
        .bind(callsign)
        .bind(role)
        .execute(pool)
        .await?;
    Ok(result.rows_affected() > 0)
}

// --- Authenticated queries ---

/// Get clubs for a callsign, with member counts
pub async fn get_clubs_for_callsign(pool: &PgPool, callsign: &str) -> Result<Vec<ClubResponse>, sqlx::Error> {
    // Use a struct for the joined query result
    struct ClubWithCount {
        id: Uuid,
        name: String,
        callsign: Option<String>,
        description: Option<String>,
        member_count: i64,
    }
    // Implement FromRow manually or use query_as with a helper
    // For now, use query_scalar approach
    sqlx::query_as::<_, /* row type */>(
        "SELECT c.id, c.name, c.callsign, c.description,
                (SELECT COUNT(*) FROM club_members WHERE club_id = c.id) as member_count
         FROM clubs c
         JOIN club_members cm ON cm.club_id = c.id
         WHERE cm.callsign = $1
         ORDER BY c.name"
    )
    .bind(callsign)
    .fetch_all(pool)
    .await
}

/// Get club detail with enriched member list
pub async fn get_club_detail(pool: &PgPool, club_id: Uuid) -> Result<Option<Club>, sqlx::Error> {
    sqlx::query_as::<_, Club>("SELECT * FROM clubs WHERE id = $1")
        .bind(club_id)
        .fetch_optional(pool)
        .await
}

/// Get members of a club, enriched with last_seen_at from participants
pub async fn get_club_members_enriched(pool: &PgPool, club_id: Uuid) -> Result<Vec<ClubMemberResponse>, sqlx::Error> {
    // Join club_members with participants to get last_seen_at
    // and check if they're a registered CW user
    sqlx::query_as::<_, /* row type */>(
        "SELECT cm.callsign, cm.role, cm.joined_at,
                p.last_seen_at,
                (p.id IS NOT NULL) as is_carrier_wave_user
         FROM club_members cm
         LEFT JOIN (
             SELECT DISTINCT ON (callsign) callsign, id, last_seen_at
             FROM participants
             ORDER BY callsign, last_seen_at DESC NULLS LAST
         ) p ON p.callsign = cm.callsign
         WHERE cm.club_id = $1
         ORDER BY cm.callsign"
    )
    .bind(club_id)
    .fetch_all(pool)
    .await
}

/// Get club activity: activities from club members
pub async fn get_club_activity(pool: &PgPool, club_id: Uuid, cursor: Option<Uuid>, limit: i64) -> Result<Vec</* ActivityResponse */>, sqlx::Error> {
    // Reuse existing activity query pattern, filtered by member callsigns
    sqlx::query_as::<_, /* row type */>(
        "SELECT a.*
         FROM activities a
         JOIN club_members cm ON cm.callsign = (
             SELECT callsign FROM users WHERE id = a.user_id
         )
         WHERE cm.club_id = $1
         AND ($2::uuid IS NULL OR a.id < $2)
         ORDER BY a.timestamp DESC
         LIMIT $3"
    )
    .bind(club_id)
    .bind(cursor)
    .bind(limit)
    .fetch_all(pool)
    .await
}

/// Check if a callsign is a member of a specific club
pub async fn is_club_member(pool: &PgPool, club_id: Uuid, callsign: &str) -> Result<bool, sqlx::Error> {
    let count: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM club_members WHERE club_id = $1 AND callsign = $2"
    )
    .bind(club_id)
    .bind(callsign)
    .fetch_one(pool)
    .await?;
    Ok(count.0 > 0)
}
```

Note: The exact row types will need to be finalized during implementation — the code above shows the SQL patterns. Use `#[derive(FromRow)]` helper structs where sqlx needs them.

**Step 2: Export from mod.rs**

Add to `db/mod.rs`:
```rust
pub mod clubs;
```

**Step 3: Build to verify**

Run: `cargo build`

**Step 4: Commit**

```bash
git add src/db/clubs.rs src/db/mod.rs
git commit -m "feat: add club database queries (CAR-108)"
```

---

## Phase 2: Server — Handlers & Routes

### Task 4: Admin club handlers

**Files:**
- Create: `~/projects/activities-server/src/handlers/clubs_admin.rs`
- Modify: `~/projects/activities-server/src/handlers/mod.rs`
- Modify: `~/projects/activities-server/src/main.rs` (admin routes)

**Step 1: Write the admin handlers**

Follow the pattern in `handlers/challenges.rs` (admin CRUD). Six endpoints:

1. `create_club` — POST `/v1/admin/clubs`
2. `update_club` — PUT `/v1/admin/clubs/:id`
3. `delete_club` — DELETE `/v1/admin/clubs/:id`
4. `add_club_members` — POST `/v1/admin/clubs/:id/members`
5. `remove_club_member` — DELETE `/v1/admin/clubs/:id/members/:callsign`
6. `update_club_member_role` — PUT `/v1/admin/clubs/:id/members/:callsign`

Each handler: extract state/path/body → call db function → return JSON response. Validate role is "admin" or "member". Return 404 for missing clubs.

**Step 2: Export from handlers/mod.rs**

**Step 3: Mount admin routes in main.rs**

Add to the `admin_routes` section:
```rust
.route("/admin/clubs", post(handlers::create_club))
.route("/admin/clubs/:id", put(handlers::update_club).delete(handlers::delete_club_handler))
.route("/admin/clubs/:id/members", post(handlers::add_club_members))
.route("/admin/clubs/:id/members/:callsign", delete(handlers::remove_club_member).put(handlers::update_club_member_role))
```

**Step 4: Build and test manually**

Run: `cargo build`
Test: `curl -X POST http://localhost:3000/v1/admin/clubs -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" -d '{"name":"Test Club"}'`

**Step 5: Commit**

```bash
git add src/handlers/clubs_admin.rs src/handlers/mod.rs src/main.rs
git commit -m "feat: add admin club management endpoints (CAR-108)"
```

---

### Task 5: Authenticated club handlers (list, detail, activity, status)

**Files:**
- Create: `~/projects/activities-server/src/handlers/clubs.rs`
- Modify: `~/projects/activities-server/src/handlers/mod.rs`
- Modify: `~/projects/activities-server/src/handlers/activity_feed.rs` (remove stubs)
- Modify: `~/projects/activities-server/src/main.rs` (auth routes)

**Step 1: Write the authenticated handlers**

Four endpoints:

1. `get_clubs` — GET `/v1/clubs` — replaces the stub in `activity_feed.rs`
   - Extract auth callsign → `db::clubs::get_clubs_for_callsign` → return list

2. `get_club_details` — GET `/v1/clubs/:id` — replaces the stub
   - Verify caller is a member → fetch club + enriched members → return detail
   - `includeMembers` query param (default true)

3. `get_club_activity` — GET `/v1/clubs/:id/activity`
   - Verify caller is a member → fetch activities from club members → cursor-paginated

4. `get_club_status` — GET `/v1/clubs/:id/status`
   - Verify caller is a member → for each member callsign:
     - Check spots table for recent entries (last 30 min) → `on_air` with spot info
     - Check participants.last_seen_at (last 15 min) → `recently_active`
     - Otherwise → `inactive`

**Step 2: Remove stubs from activity_feed.rs**

Delete the `get_clubs` and `get_club_details` stub functions.

**Step 3: Update routes in main.rs**

Replace the stub routes in `auth_routes`:
```rust
.route("/clubs", get(handlers::get_clubs))
.route("/clubs/:id", get(handlers::get_club_details))
.route("/clubs/:id/activity", get(handlers::get_club_activity))
.route("/clubs/:id/status", get(handlers::get_club_status))
```

**Step 4: Build and test**

Run: `cargo build`
Test: Register a user, create a club via admin, add user as member, then hit GET /v1/clubs.

**Step 5: Commit**

```bash
git add src/handlers/clubs.rs src/handlers/activity_feed.rs src/handlers/mod.rs src/main.rs
git commit -m "feat: add authenticated club endpoints (CAR-108)"
```

---

### Task 6: Server integration testing

**Files:**
- Modify tests if they exist, or test manually with curl

**Step 1: End-to-end test flow**

```bash
# 1. Create club
curl -X POST localhost:3000/v1/admin/clubs \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Radio Club","callsign":"W1TEST","description":"A test club"}'

# 2. Add members
curl -X POST localhost:3000/v1/admin/clubs/$CLUB_ID/members \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"members":[{"callsign":"K1ABC","role":"admin"},{"callsign":"W2DEF","role":"member"}]}'

# 3. Get clubs as authenticated user
curl localhost:3000/v1/clubs -H "Authorization: Bearer $USER_TOKEN"

# 4. Get club detail
curl localhost:3000/v1/clubs/$CLUB_ID -H "Authorization: Bearer $USER_TOKEN"

# 5. Get member status
curl localhost:3000/v1/clubs/$CLUB_ID/status -H "Authorization: Bearer $USER_TOKEN"
```

**Step 2: Verify non-member access is denied**

Authenticated user who is NOT a member of the club should get 403 on detail/activity/status.

**Step 3: Commit any fixes**

---

## Phase 3: iOS — Data Model & Sync

### Task 7: SwiftData models for Club and ClubMember

**Files:**
- Create: `CarrierWave/Models/Club.swift`
- Modify: Container setup (wherever `ModelContainer` is configured — check `CarrierWaveApp.swift` or similar)

**Step 1: Create Club model**

Follow the pattern in `QSO.swift` — `@Model nonisolated final class`:

```swift
@Model
nonisolated final class Club {
    var serverId = UUID()
    var name = ""
    var callsign: String?
    var clubDescription: String?
    var lastSyncedAt = Date()

    @Relationship(deleteRule: .cascade, inverse: \ClubMember.club)
    private var membersRelation: [ClubMember]?

    var members: [ClubMember] {
        get { membersRelation ?? [] }
        set { membersRelation = newValue }
    }

    init(serverId: UUID, name: String, callsign: String? = nil, clubDescription: String? = nil) {
        self.serverId = serverId
        self.name = name
        self.callsign = callsign
        self.clubDescription = clubDescription
        self.lastSyncedAt = Date()
    }
}
```

**Step 2: Create ClubMember model**

```swift
@Model
nonisolated final class ClubMember {
    var callsign = ""
    var role = "member"
    var lastSeenAt: Date?
    var lastGrid: String?
    var club: Club?

    init(callsign: String, role: String = "member", club: Club) {
        self.callsign = callsign
        self.role = role
        self.club = club
    }
}
```

**Step 3: Add to ModelContainer configuration**

Find where the model container is set up and add `Club.self` and `ClubMember.self` to the schema.

**Step 4: Build**

Run: `xc build`

**Step 5: Commit**

```bash
git add CarrierWave/Models/Club.swift
git commit -m "feat: add Club and ClubMember SwiftData models (CAR-108)"
```

---

### Task 8: Update ActivitiesClient+Clubs DTOs and endpoints

**Files:**
- Modify: `CarrierWave/Services/ActivitiesClient+Clubs.swift`

**Step 1: Update DTOs to match new server responses**

The existing `ClubDTO`, `ClubDetailDTO`, and `ClubMemberDTO` need to align with the server response shapes. Update them:

- `ClubDTO`: add `callsign` field
- `ClubMemberDTO`: add `role`, `joinedAt`, `lastSeenAt`, `lastGrid` fields
- Add `MemberStatusDTO` with `callsign`, `status` (enum: onAir/recentlyActive/inactive), `spotInfo`, `lastSeenAt`
- Add `SpotInfoDTO` with `frequency`, `mode`, `source`, `spottedAt`

**Step 2: Add new endpoint methods**

- `fetchClubActivity(clubId:, sourceURL:, authToken:, cursor:)` → paginated activity list
- `fetchClubStatus(clubId:, sourceURL:, authToken:)` → `[MemberStatusDTO]`

Follow the existing `getMyClubs`/`getClubDetails` pattern.

**Step 3: Build**

Run: `xc build`

**Step 4: Commit**

```bash
git add CarrierWave/Services/ActivitiesClient+Clubs.swift
git commit -m "feat: update club DTOs and add activity/status endpoints (CAR-108)"
```

---

### Task 9: ClubSyncService

**Files:**
- Create: `CarrierWave/Services/ClubSyncService.swift`

**Step 1: Create the sync service**

Follow `SyncService.swift` pattern — `@MainActor` class with background work on actors:

```swift
@MainActor
class ClubSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?

    /// In-memory set of all club member callsigns for O(1) lookup
    @Published private(set) var clubMemberCallsigns: Set<String> = []

    /// Map of callsign → [club name] for display
    @Published private(set) var clubsByCallsign: [String: [String]] = [:]

    private let container: ModelContainer
    private let activitiesClient: ActivitiesClient

    func sync() async {
        // 1. Fetch clubs from server
        // 2. For each club, fetch detail with members
        // 3. Reconcile into SwiftData (full replace per club)
        // 4. Rebuild in-memory callsign set
        // 5. Delete local clubs no longer returned by server
    }

    /// Rebuild in-memory lookups from SwiftData
    func rebuildCallsignCache() {
        // Fetch all ClubMembers from SwiftData
        // Build Set<String> and [String: [String]] dictionary
    }

    /// Check if a callsign is a club member
    func clubs(for callsign: String) -> [String] {
        clubsByCallsign[callsign.uppercased()] ?? []
    }
}
```

**Step 2: Build**

Run: `xc build`

**Step 3: Commit**

```bash
git add CarrierWave/Services/ClubSyncService.swift
git commit -m "feat: add ClubSyncService with offline caching (CAR-108)"
```

---

### Task 10: Wire ClubSyncService into app lifecycle

**Files:**
- Modify: App entry point (wherever `SyncService` is created/injected)
- Modify: Scene delegate or main app view for foreground resume triggers

**Step 1: Create ClubSyncService alongside other sync services**

Instantiate in the app's root and pass to views that need it. Trigger initial sync on app launch when community features are enabled.

**Step 2: Add foreground resume trigger**

On `scenePhase` change to `.active`, call `clubSyncService.sync()`.

**Step 3: Build and test**

Run: `xc build`
Verify: App launches, club sync runs (may return empty if no clubs configured).

**Step 4: Commit**

```bash
git commit -m "feat: wire ClubSyncService into app lifecycle (CAR-108)"
```

---

## Phase 4: iOS — Club Hub UI

### Task 11: Club list view

**Files:**
- Create: `CarrierWave/Views/Clubs/ClubListView.swift`

**Step 1: Create the club list view**

Show user's clubs with member count. Use `@State` + `.task` pattern (not `@Query`):

```swift
struct ClubListView: View {
    @State private var clubs: [Club] = []
    @Environment(\.modelContext) var modelContext

    var body: some View {
        List(clubs) { club in
            NavigationLink(value: club.serverId) {
                ClubRow(club: club)
            }
        }
        .navigationTitle("Clubs")
        .task { loadClubs() }
    }
}
```

**Step 2: Build**

Run: `xc build`

**Step 3: Commit**

```bash
git add CarrierWave/Views/Clubs/ClubListView.swift
git commit -m "feat: add club list view (CAR-108)"
```

---

### Task 12: Club detail view with members, activity, and map tabs

**Files:**
- Create: `CarrierWave/Views/Clubs/ClubDetailView.swift`
- Create: `CarrierWave/Views/Clubs/ClubMemberRow.swift`
- Create: `CarrierWave/Views/Clubs/ClubActivityView.swift`
- Create: `CarrierWave/Views/Clubs/ClubMapView.swift`

**Step 1: Create ClubDetailView with tab picker**

Three sections via `Picker` with `.segmented` style: Members, Activity, Map.

- **Members tab**: List of `ClubMemberRow` with status dots (green/yellow/grey). Status fetched live from `/clubs/:id/status` on appear.
- **Activity tab**: Paginated activity feed from `/clubs/:id/activity`. Reuse existing `ActivityItemRow` pattern if possible.
- **Map tab**: Map with pins at member grid squares. Use `MaidenheadConverter.coordinate(from:)` + `Annotation` pattern from `SidebarMapView`.

**Step 2: Create ClubMemberRow**

Show callsign, role badge ("Admin" if admin), status dot, and last grid.

**Step 3: Create ClubMapView**

Pin per member at their `lastGrid` coordinate. Color by status when available.

**Step 4: Build**

Run: `xc build`

**Step 5: Commit**

```bash
git add CarrierWave/Views/Clubs/
git commit -m "feat: add club detail view with members, activity, and map (CAR-108)"
```

---

### Task 13: Club stats dashboard

**Files:**
- Create: `CarrierWave/Views/Clubs/ClubStatsView.swift`

**Step 1: Create stats view**

Computed locally from club activity data. Show:
- Total QSOs this week/month (from activity feed)
- Most active member
- Band/mode breakdown
- Grid coverage count

This can be a section within `ClubDetailView` or a separate scrollable view.

**Step 2: Build**

Run: `xc build`

**Step 3: Commit**

```bash
git add CarrierWave/Views/Clubs/ClubStatsView.swift
git commit -m "feat: add club stats dashboard (CAR-108)"
```

---

### Task 14: Navigation — add Clubs to Activity tab

**Files:**
- Modify: `CarrierWave/Views/Activity/ActivityView.swift` (add clubs section)
- Or create navigation from the Activity tab's existing structure

**Step 1: Add Clubs section**

The Activity tab already handles friends and activity feed. Add a "Clubs" section with a NavigationLink to `ClubListView`. This keeps all social features together.

The `AppTab.activity` description already says "Friends, clubs, and activity feed" — so this is the right home.

**Step 2: Build**

Run: `xc build`

**Step 3: Commit**

```bash
git commit -m "feat: add clubs navigation to Activity tab (CAR-108)"
```

---

## Phase 5: iOS — Logger & QSO Integration

### Task 15: Club badge in logger callsign input

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView+FormFields.swift`
- Modify: `CarrierWave/Views/Logger/LoggerView.swift` (add ClubSyncService dependency)

**Step 1: Access ClubSyncService in LoggerView**

Inject `ClubSyncService` via environment or pass it down. In `onCallsignChanged`, after the existing QRZ lookup debounce, check:

```swift
let matchingClubs = clubSyncService.clubs(for: newCallsign)
```

**Step 2: Show club badge**

If `matchingClubs` is non-empty, show a small badge below or beside the callsign field:

```swift
if !matchingClubs.isEmpty {
    HStack(spacing: 4) {
        Image(systemName: "person.3.fill")
            .font(.caption2)
        Text(matchingClubs.joined(separator: ", "))
            .font(.caption)
    }
    .foregroundStyle(.blue)
    .padding(.horizontal)
}
```

**Step 3: Build**

Run: `xc build`

**Step 4: Commit**

```bash
git commit -m "feat: show club badge in logger when working a club member (CAR-108)"
```

---

### Task 16: Club badge on QSO detail

**Files:**
- Modify: `CarrierWave/Views/Logs/QSODetailView.swift`

**Step 1: Add club badge section**

After the existing sync status section, check if the QSO's callsign is a club member:

```swift
let matchingClubs = clubSyncService.clubs(for: qso.callsign)
if !matchingClubs.isEmpty {
    Section("Club") {
        ForEach(matchingClubs, id: \.self) { clubName in
            Label(clubName, systemImage: "person.3.fill")
        }
    }
}
```

**Step 2: Build**

Run: `xc build`

**Step 3: Commit**

```bash
git commit -m "feat: show club badges on QSO detail view (CAR-108)"
```

---

### Task 17: Club member highlighting in spots

**Files:**
- Modify: spot display view (likely `SpotSummaryView.swift` or the spot row view)

**Step 1: Check spot callsign against club member set**

When rendering a spot row, if the spotted callsign is in `clubMemberCallsigns`, add a club indicator (small icon or colored badge).

**Step 2: Build**

Run: `xc build`

**Step 3: Commit**

```bash
git commit -m "feat: highlight club member spots (CAR-108)"
```

---

### Task 18: Club badge in activity feed

**Files:**
- Modify: Activity feed row view (wherever individual feed items are rendered)

**Step 1: Add club tag to feed items**

If the activity's callsign is a club member, show a club tag alongside the activity:

```swift
if !matchingClubs.isEmpty {
    Text(matchingClubs.first!)
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.blue.opacity(0.15))
        .clipShape(Capsule())
}
```

**Step 2: Build**

Run: `xc build`

**Step 3: Commit**

```bash
git commit -m "feat: show club tags in activity feed (CAR-108)"
```

---

## Phase 6: Polish & Documentation

### Task 19: Update FILE_INDEX.md

**Files:**
- Modify: `docs/FILE_INDEX.md`

Add all new files created in this feature.

### Task 20: Update CHANGELOG.md

**Files:**
- Modify: `CHANGELOG.md`

Add under `[Unreleased]`:
```markdown
### Added
- Club support: view your clubs, members, activity, and stats (CAR-108)
- Club member detection in logger — see when you're working a club member
- Club badges on QSO detail and activity feed
- Club member map showing member grid locations
- Club member highlighting in spot list
```

### Task 21: Update Linear

Comment on CAR-108 with implementation summary. Move to Done if all surfaces are working.

```bash
linear issue comment add CAR-108 -b "Clubs feature implemented: server CRUD + authenticated endpoints, SwiftData models with offline sync, club hub with members/activity/map/stats, logger integration, QSO detail badges, spot highlighting, activity feed tags."
linear issue update CAR-108 -s "Done"
```
