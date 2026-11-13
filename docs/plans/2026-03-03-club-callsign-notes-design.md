# Club-Approved Callsign Notes Recommendations

**Date:** 2026-03-03
**Status:** Approved

## Problem

Clubs can maintain PoLo-style callsign notes files (member rosters with emojis/annotations), but users have to manually discover and add the URL. We want the server to store club notes file URLs so the app can recommend them to users who are members of those clubs.

## Design Decisions

- **One notes file per club** — simple `notes_url` column on `clubs` table
- **Recommendation only** — no auto-adding; user opts in via Callsign Notes settings
- **Club admins manage** — authenticated endpoint checks club admin role
- **One-tap add** — tapping "Add" instantly creates a `CallsignNotesSource` with no form

## Server Changes

### Migration

Add to `clubs` table:

```sql
ALTER TABLE clubs ADD COLUMN notes_url TEXT;
ALTER TABLE clubs ADD COLUMN notes_title TEXT;
```

### API Response Changes

`ClubResponse` and `ClubDetailResponse` gain:

```rust
pub notes_url: Option<String>,
pub notes_title: Option<String>,
```

### New Endpoint

`PUT /v1/clubs/:id/notes` — authenticated, caller must be club admin.

```rust
struct UpdateClubNotesRequest {
    notes_url: Option<String>,   // null to clear
    notes_title: Option<String>, // null to clear
}
```

Validates URL starts with `https://`. No content validation.

### Existing Admin Endpoint

`UpdateClubRequest` also gains `notes_url` and `notes_title` optional fields for server-admin management.

## App Changes

### Model Updates

`Club` SwiftData model gains:

```swift
var notesURL: String?
var notesTitle: String?
```

`ClubDTO` and `ClubDetailDTO` gain matching Codable fields. `ClubsSyncService` maps them during sync.

### UI: Callsign Notes Settings

New "Recommended" section at top of `CallsignNotesSettingsView`:

- **Shown when:** user belongs to clubs with `notesURL` set AND the URL isn't already in their `CallsignNotesSource` list
- **Each row:** Club name, notes title (subtitle if different from club name), "Add" button
- **On tap:** Creates `CallsignNotesSource(title: notesTitle ?? clubName, url: notesURL, isEnabled: true)`, triggers cache refresh
- **After add:** Row disappears from recommendations, source appears in regular list

### What's NOT Included

- No auto-adding notes sources
- No in-app admin UI for setting the notes URL
- No content validation on server
- No special "club source" flag — becomes a regular source once added
- No notification/badge for new recommendations
