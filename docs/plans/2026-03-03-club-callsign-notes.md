# Club-Approved Callsign Notes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let clubs register a PoLo callsign notes file URL on the server, and recommend it to club members in the app's Callsign Notes settings.

**Architecture:** Add `notes_url` and `notes_title` columns to the server's `clubs` table. Expose them in existing club API responses. Add a club-admin endpoint to manage them. In the app, sync the new fields to the `Club` model and show a "Recommended" section in `CallsignNotesSettingsView`.

**Tech Stack:** Rust/axum/sqlx (server), SwiftUI/SwiftData (app)

---

### Task 1: Server Migration — Add notes columns to clubs table

**Files:**
- Create: `migrations/010_club_notes.sql` (in activities-server)

**Step 1: Write migration**

```sql
ALTER TABLE clubs ADD COLUMN notes_url TEXT;
ALTER TABLE clubs ADD COLUMN notes_title TEXT;
```

**Step 2: Run migration to verify**

Run: `cd /Users/jsvana/projects/activities-server && cargo sqlx migrate run`
Expected: Migration 010 applied successfully

**Step 3: Commit**

```bash
git add migrations/010_club_notes.sql
git commit -m "feat: add notes_url and notes_title columns to clubs table"
```

---

### Task 2: Server Models — Add notes fields to structs

**Files:**
- Modify: `src/models/club.rs`

**Step 1: Add fields to `Club` database row struct (~line 17)**

Add before `created_at`:

```rust
pub notes_url: Option<String>,
pub notes_title: Option<String>,
```

**Step 2: Add fields to `ClubResponse` (~line 43)**

Add after `member_count`:

```rust
pub notes_url: Option<String>,
pub notes_title: Option<String>,
```

**Step 3: Add fields to `ClubDetailResponse` (~line 54)**

Add after `description`:

```rust
pub notes_url: Option<String>,
pub notes_title: Option<String>,
```

**Step 4: Add fields to `UpdateClubRequest` (~line 121)**

Add after `description`:

```rust
pub notes_url: Option<Option<String>>,
pub notes_title: Option<Option<String>>,
```

Note: `Option<Option<String>>` — outer Option = field present in request, inner Option = value or null (to clear).

**Step 5: Add new request type for club-admin notes update**

Add after `UpdateMemberRoleRequest`:

```rust
#[derive(Debug, Deserialize)]
pub struct UpdateClubNotesRequest {
    pub notes_url: Option<String>,
    pub notes_title: Option<String>,
}
```

**Step 6: Verify it compiles**

Run: `cd /Users/jsvana/projects/activities-server && cargo check`
Expected: Compiles (may have warnings about unused fields — that's fine)

**Step 7: Commit**

```bash
git add src/models/club.rs
git commit -m "feat: add notes_url and notes_title to club model structs"
```

---

### Task 3: Server DB — Update queries for notes fields

**Files:**
- Modify: `src/db/clubs.rs`

**Step 1: Add notes fields to `ClubWithCount` struct (~line 21)**

Add before `member_count`:

```rust
pub notes_url: Option<String>,
pub notes_title: Option<String>,
```

**Step 2: Update `update_club()` function (~line 79)**

Add COALESCE lines for the new fields in the UPDATE query, matching the existing pattern for `callsign` and `description`:

```sql
notes_url = COALESCE($5, notes_url),
notes_title = COALESCE($6, notes_title)
```

Bind the new parameters. Note: to support clearing (setting to null), use the nested Option pattern — when outer is `Some(None)`, explicitly set NULL rather than COALESCE.

**Step 3: Add `update_club_notes()` function**

Add a new function after `update_club()`:

```rust
pub async fn update_club_notes(
    pool: &PgPool,
    club_id: Uuid,
    notes_url: Option<String>,
    notes_title: Option<String>,
) -> Result<Option<Club>, AppError> {
    let club = sqlx::query_as::<_, Club>(
        "UPDATE clubs SET notes_url = $2, notes_title = $3, updated_at = now()
         WHERE id = $1
         RETURNING *"
    )
    .bind(club_id)
    .bind(notes_url)
    .bind(notes_title)
    .fetch_optional(pool)
    .await?;
    Ok(club)
}
```

**Step 4: Update SELECT queries in `list_all_clubs()` and `get_clubs_for_callsign()`**

These use `SELECT c.id, c.name, c.callsign, c.description, COUNT(...)` — add `c.notes_url, c.notes_title` to the SELECT list and GROUP BY clause, matching the updated `ClubWithCount` struct.

**Step 5: Update `get_club_detail()` query**

Add `notes_url, notes_title` to the SELECT (it returns full `Club` struct via `query_as::<_, Club>`, so this should work automatically since the struct now has the fields — verify the query uses `SELECT *` or enumerate all columns).

**Step 6: Verify it compiles**

Run: `cargo check`

**Step 7: Commit**

```bash
git add src/db/clubs.rs
git commit -m "feat: add notes fields to club DB queries"
```

---

### Task 4: Server Handlers — Update responses and add notes endpoint

**Files:**
- Modify: `src/handlers/clubs.rs`
- Modify: `src/main.rs`

**Step 1: Update `get_clubs()` handler response mapping (~line 30)**

Where `ClubResponse` is built from `ClubWithCount`, add the new fields:

```rust
notes_url: club.notes_url,
notes_title: club.notes_title,
```

**Step 2: Update `get_club_details()` handler response mapping (~line 60)**

Where `ClubDetailResponse` is built from `Club`, add:

```rust
notes_url: club.notes_url,
notes_title: club.notes_title,
```

**Step 3: Add `update_club_notes()` handler**

```rust
pub async fn update_club_notes(
    State(state): State<AppState>,
    Path(club_id): Path<Uuid>,
    auth: AuthContext,
    Json(req): Json<UpdateClubNotesRequest>,
) -> Result<Json<DataResponse<ClubResponse>>, AppError> {
    // Verify caller is a member
    let is_member = db::clubs::is_club_member(&state.pool, club_id, &auth.callsign).await?;
    if !is_member {
        return Err(AppError::Forbidden);
    }

    // Verify caller is an admin of this club
    let members = db::clubs::get_club_members_enriched(&state.pool, club_id).await?;
    let caller_member = members.iter().find(|m| m.callsign.eq_ignore_ascii_case(&auth.callsign));
    match caller_member {
        Some(m) if m.role == "admin" => {}
        _ => return Err(AppError::Forbidden),
    }

    // Validate URL if provided
    if let Some(ref url) = req.notes_url {
        if !url.starts_with("https://") {
            return Err(AppError::BadRequest("notes_url must start with https://".into()));
        }
    }

    // Update
    let club = db::clubs::update_club_notes(&state.pool, club_id, req.notes_url, req.notes_title)
        .await?
        .ok_or(AppError::ClubNotFound { club_id })?;

    // Build response with member count
    let clubs = db::clubs::get_clubs_for_callsign(&state.pool, &auth.callsign).await?;
    let club_with_count = clubs.into_iter().find(|c| c.id == club_id);
    let member_count = club_with_count.map(|c| c.member_count).unwrap_or(0);

    Ok(Json(DataResponse {
        data: ClubResponse {
            id: club.id,
            name: club.name,
            callsign: club.callsign,
            description: club.description,
            notes_url: club.notes_url,
            notes_title: club.notes_title,
            member_count,
        },
    }))
}
```

**Step 4: Register route in `main.rs`**

In the authenticated routes block (~line 162), add after the existing club routes:

```rust
.route("/clubs/:id/notes", put(handlers::update_club_notes))
```

**Step 5: Also update admin `update_club` handler and `list_clubs_admin`/`create_club` handlers**

Ensure the admin responses also include the new fields where `ClubResponse` is constructed.

**Step 6: Verify it compiles**

Run: `cargo check`

**Step 7: Commit**

```bash
git add src/handlers/clubs.rs src/main.rs
git commit -m "feat: add club notes endpoint and update responses"
```

---

### Task 5: App Models — Add notes fields to Club and DTOs

**Files:**
- Modify: `CarrierWave/Models/Club.swift` (~lines 25-29)
- Modify: `CarrierWave/Services/ActivitiesClient+Clubs.swift` (~lines 117-133)

**Step 1: Add properties to `Club` SwiftData model**

After `clubDescription` (~line 28):

```swift
var notesURL: String?
var notesTitle: String?
```

**Step 2: Update `Club.init()` to include new parameters**

Add parameters with defaults:

```swift
notesURL: String? = nil,
notesTitle: String? = nil,
```

And assignments in the init body.

**Step 3: Add fields to `ClubDTO`**

After `description` (~line 122):

```swift
let notesUrl: String?
let notesTitle: String?
```

**Step 4: Add fields to `ClubDetailDTO`**

After `description` (~line 132):

```swift
let notesUrl: String?
let notesTitle: String?
```

**Step 5: Commit**

```bash
git add CarrierWave/Models/Club.swift CarrierWave/Services/ActivitiesClient+Clubs.swift
git commit -m "feat: add notesURL and notesTitle to Club model and DTOs"
```

---

### Task 6: App Sync — Map notes fields during club sync

**Files:**
- Modify: `CarrierWave/Services/ClubsSyncService.swift`

**Step 1: Update `updateLocalClubs(from:context:)` (~line 134)**

In the section that creates new clubs or updates existing ones, map the new fields:

```swift
club.notesURL = dto.notesUrl
club.notesTitle = dto.notesTitle
```

Add to both the "create new" and "update existing" branches.

**Step 2: Update `updateClubFromDetails(_:context:)` (~line 177)**

Same mapping when syncing from `ClubDetailDTO`:

```swift
club.notesURL = dto.notesUrl
club.notesTitle = dto.notesTitle
```

**Step 3: Commit**

```bash
git add CarrierWave/Services/ClubsSyncService.swift
git commit -m "feat: sync club notes fields from server"
```

---

### Task 7: App UI — Add Recommended section to Callsign Notes settings

**Files:**
- Modify: `CarrierWave/Views/Settings/CallsignNotesSettingsView.swift`

**Step 1: Add state for clubs with notes**

Add a property to load clubs that have notes URLs:

```swift
@State private var recommendedClubs: [(club: Club, notesURL: String, notesTitle: String)] = []
```

**Step 2: Add `.task` to load recommendations**

In the view body, add a `.task` modifier that:
1. Fetches all `Club` objects where `notesURL != nil`
2. Filters out any whose `notesURL` already matches an existing `CallsignNotesSource.url`
3. Populates `recommendedClubs`

```swift
.task {
    await loadRecommendations()
}
```

**Step 3: Add `loadRecommendations()` method**

```swift
private func loadRecommendations() async {
    var descriptor = FetchDescriptor<Club>(
        predicate: #Predicate<Club> { $0.notesURL != nil }
    )
    guard let clubs = try? modelContext.fetch(descriptor) else { return }

    let existingURLs = Set(sources.map(\.url))
    recommendedClubs = clubs.compactMap { club in
        guard let url = club.notesURL, !existingURLs.contains(url) else { return nil }
        let title = club.notesTitle ?? club.name
        return (club: club, notesURL: url, notesTitle: title)
    }
}
```

**Step 4: Add recommended section to the List**

Add before the existing sources section (so it appears at top):

```swift
if !recommendedClubs.isEmpty {
    Section {
        ForEach(recommendedClubs, id: \.club.serverId) { rec in
            recommendedRow(rec)
        }
    } header: {
        Text("Recommended")
    }
}
```

**Step 5: Add `recommendedRow` view builder**

```swift
@ViewBuilder
private func recommendedRow(_ rec: (club: Club, notesURL: String, notesTitle: String)) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 2) {
            Text(rec.notesTitle)
                .font(.body)
            Text(rec.club.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Add") {
            addSource(title: rec.notesTitle, url: rec.notesURL)
            // Remove from recommendations
            recommendedClubs.removeAll { $0.club.serverId == rec.club.serverId }
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
    }
}
```

Note: If `notesTitle == club.name`, only show the title (skip the subtitle). Adjust the row accordingly.

**Step 6: Commit**

```bash
git add CarrierWave/Views/Settings/CallsignNotesSettingsView.swift
git commit -m "feat: add Recommended section for club callsign notes"
```

---

### Task 8: Build verification and cleanup

**Step 1: Build the server**

Run: `cd /Users/jsvana/projects/activities-server && cargo build`
Expected: Compiles without errors

**Step 2: Build the app**

Run: `xc build` (local) or create `.needs-quality-check` (cloud)

**Step 3: Update FILE_INDEX.md if any new files were created**

**Step 4: Update CHANGELOG.md**

Under `[Unreleased]`, add:

```markdown
### Added
- Club-approved callsign notes — clubs can register a PoLo notes file URL, recommended to members in Callsign Notes settings
```

**Step 5: Commit cleanup**

```bash
git add CHANGELOG.md docs/FILE_INDEX.md
git commit -m "docs: update changelog and file index for club notes"
```
