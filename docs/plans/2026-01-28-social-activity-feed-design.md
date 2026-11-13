# Social Activity Feed Design

> **Status:** Draft
> **Date:** 2026-01-28
> **Author:** Claude + jsvana

## Overview

Transform the Challenges tab into a social Activity tab that shows friends' and club members' notable radio activities, while preserving existing challenge functionality.

## Goals

1. Create a social experience around amateur radio activity
2. Enable friend connections with bi-directional confirmation
3. Support clubs with membership derived from Ham2K Polo callsign notes lists
4. Surface notable achievements (new DXCC, streaks, personal bests, etc.)
5. Enable sharing accomplishments via branded image cards

## Non-Goals (v1)

- User-created clubs (admin-only for now)
- Reactions or comments on feed items
- Maps embedded in feed items
- Real-time/push notifications (polling is acceptable)

---

## Tab Structure

The **Challenges tab** becomes the **Activity tab** with two sections:

### Your Challenges (Top Section)

- Active challenge progress cards
- Completed challenges (collapsible)
- "Browse Challenges" navigation link
- Existing `ChallengesView` content, condensed

### Recent Activity (Main Feed)

- Scrolling feed of activity from friends and club members
- Filter bar: All | Friends | [Club names...]
- Each item: callsign, activity type, timestamp, details, share button

---

## Social Graph

### Friends

Bi-directional connections requiring confirmation from both parties.

**Discovery Methods:**

| Method | Description |
|--------|-------------|
| Callsign search | Search by callsign, send request |
| QSO suggestions | After logging QSO, option to add as friend (if they're a Carrier Wave user) |
| Invite links | Shareable link; recipient taps to send friend request |

**Request Flow:**

1. User A sends request (via search, QSO, or invite link)
2. User B sees request in "Friend Requests" section
3. User B accepts or declines
4. On accept, both users see each other's activity in feed

### Clubs

Clubs are defined by a name and a link to a Ham2K Polo callsign notes list. Membership is derived from the list contents, not managed in-app.

**Club Definition:**

| Field | Description |
|-------|-------------|
| `name` | Display name (e.g., "Pacific Northwest DX Club") |
| `poloNotesListURL` | URL to Polo callsign notes list |
| `description` | Optional description |

**Membership:**

- Carrier Wave fetches the Polo notes list periodically
- Callsigns in the list = club members
- User's club memberships determined by whether their callsign appears in any registered club's list
- No join/leave actions in Carrier Wave

**Creation:**

Admin-only for v1. Clubs registered via backend/admin tooling.

---

## Activity Feed

### Activity Types

| Type | Trigger | Example |
|------|---------|---------|
| `challengeTierUnlock` | User reaches new tier | "W1ABC reached Gold tier in DXCC Challenge" |
| `challengeCompletion` | User completes challenge | "K2XYZ completed the POTA Kilo challenge" |
| `newDXCCEntity` | First contact with a country | "N3QRS worked Japan for the first time" |
| `newBand` | First QSO on a band | "W4DEF made first 6m contact" |
| `newMode` | First QSO with a mode | "KD5GHI made first FT8 contact" |
| `dxContact` | QSO over 5000km | "WA6JKL worked VK2ABC (14,231 km)" |
| `potaActivation` | POTA activation logged | "W7MNO activated US-1234 (5 QSOs)" |
| `sotaActivation` | SOTA activation logged | "W8PQR activated W7W/LC-001" |
| `dailyStreak` | Daily QSO streak achieved/extended | "W9STU hit a 30-day QSO streak" |
| `potaDailyStreak` | Daily POTA streak achieved/extended | "W9STU hit a 14-day POTA streak" |
| `personalBest` | New personal record | "W0VWX set new distance record: 18,402 km" |

### Feed Item Structure

```
┌─────────────────────────────────────────┐
│ [Avatar] W1ABC                    2h ago│
│ 🏆 Reached Gold tier in DXCC Challenge  │
│                                  [Share]│
└─────────────────────────────────────────┘
```

Fields:
- Callsign (tappable → profile/stats view)
- Activity icon + description
- Relative timestamp
- Share button

### Filtering

Filter bar with options:
- **All** — Friends + all clubs
- **Friends** — Friends only
- **[Club Name]** — One chip per club user belongs to

---

## Sharing

### Shareable Content

1. **Individual feed items** — Any activity item
2. **Summary cards** — Weekly/monthly/custom date range summaries

### Image Card Format

Branded image cards (Spotify Wrapped style):
- Carrier Wave logo/branding
- User's callsign
- Key stats or achievement details
- Visually appealing, social-media-ready

**Individual Item Example:**
```
┌────────────────────────────┐
│     🏆 CARRIER WAVE        │
│                            │
│  W1ABC worked Japan        │
│  for the first time!       │
│                            │
│  20m · SSB · 2026-01-28    │
└────────────────────────────┘
```

**Summary Card Example:**
```
┌────────────────────────────┐
│     📻 CARRIER WAVE        │
│     My Week in Radio       │
│                            │
│  47 QSOs                   │
│  12 countries              │
│  Furthest: 14,231 km       │
│  🔥 7-day streak           │
│                            │
│  W1ABC · Jan 21-28, 2026   │
└────────────────────────────┘
```

### Share Flow

1. Tap share button on feed item (or "Share Summary" elsewhere)
2. App renders SwiftUI view to UIImage
3. iOS share sheet appears
4. User selects destination

---

## Data Models

### Client-Side (SwiftData)

```swift
@Model
final class Friendship {
    var id: UUID
    var friendCallsign: String
    var friendUserId: String
    var status: FriendshipStatus  // .pending, .accepted, .declined
    var requestedAt: Date
    var acceptedAt: Date?
    var isOutgoing: Bool  // true if I sent the request
}

@Model
final class Club {
    var id: UUID
    var name: String
    var poloNotesListURL: String
    var descriptionText: String?
    var memberCallsignsData: Data  // JSON array of callsigns
    var lastSyncedAt: Date

    var memberCallsigns: [String] { /* decode from data */ }
    func isMember(callsign: String) -> Bool { /* check list */ }
}

@Model
final class ActivityItem {
    var id: UUID
    var callsign: String
    var activityType: String  // raw value of ActivityType
    var timestamp: Date
    var detailsData: Data  // JSON for type-specific info
    var isOwn: Bool
    var challengeId: UUID?
}

enum ActivityType: String, Codable {
    case challengeTierUnlock
    case challengeCompletion
    case newDXCCEntity
    case newBand
    case newMode
    case dxContact
    case potaActivation
    case sotaActivation
    case dailyStreak
    case potaDailyStreak
    case personalBest
}

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case declined
}
```

---

## API Endpoints

All endpoints added to existing challenges server.

### Friends

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/friends/request` | Send friend request (callsign or invite token) |
| `GET` | `/friends/requests` | List pending incoming requests |
| `POST` | `/friends/requests/{id}/accept` | Accept request |
| `POST` | `/friends/requests/{id}/decline` | Decline request |
| `GET` | `/friends` | List confirmed friends |
| `DELETE` | `/friends/{id}` | Remove friend |
| `GET` | `/friends/invite-link` | Generate shareable invite link |

### Clubs

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/clubs` | List clubs user belongs to |
| `GET` | `/clubs/{id}` | Club details + member list |
| `POST` | `/clubs` | Create club (admin only) |

### Activity Feed

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/feed` | Paginated feed (friends + clubs) |
| `GET` | `/feed?filter=friends` | Friends only |
| `GET` | `/feed?filter=club:{id}` | Specific club only |
| `POST` | `/activities` | Report notable activity |

### Activity Reporting

Client detects notable events locally and reports to server:

```json
POST /activities
{
  "type": "newDXCCEntity",
  "timestamp": "2026-01-28T15:30:00Z",
  "details": {
    "entity": "Japan",
    "entityCode": "JA",
    "band": "20m",
    "mode": "SSB"
  }
}
```

---

## UI Components

### Activity Tab Layout

```
NavigationStack
├── ScrollView
│   ├── Your Challenges Section
│   │   ├── Header: "Your Challenges" + "Browse" link
│   │   ├── Active challenge cards
│   │   └── Completed challenges (collapsed)
│   │
│   ├── Filter Bar (horizontal scroll)
│   │   └── Chips: All | Friends | Club A | Club B...
│   │
│   └── Recent Activity Section
│       ├── Header: "Recent Activity"
│       └── LazyVStack of ActivityItemRow
│
├── Toolbar
│   ├── Leading: Friend requests badge
│   └── Trailing: Refresh
│
└── Navigation destinations
    ├── ChallengeDetailView (existing)
    ├── BrowseChallengesView (existing)
    ├── FriendRequestsView (new)
    ├── FriendProfileView (new)
    └── ClubDetailView (new)
```

### New Views

| View | Purpose |
|------|---------|
| `ActivityView` | Main tab view (replaces ChallengesView) |
| `ActivityItemRow` | Single feed item display |
| `FilterBar` | Horizontal scrolling filter chips |
| `FriendRequestsView` | List pending requests, accept/decline |
| `FriendProfileView` | View friend's stats and activity |
| `ClubDetailView` | Club info, member list, club activity |
| `ShareCardView` | SwiftUI view for rendering share images |
| `SummaryCardSheet` | Configure and generate summary cards |

---

## Implementation Phases

### Phase 1: Activity Tab Shell
- Rename Challenges tab to Activity
- Add "Your Challenges" section (move existing content)
- Add empty "Recent Activity" section with placeholder

### Phase 2: Friends System
- Friendship data model
- API endpoints for friend requests
- Friend request UI (send, receive, accept/decline)
- Friends list view

### Phase 3: Activity Detection
- Detect notable events during QSO import/sync
- Local notification when personal milestones hit
- Report activities to server

### Phase 4: Activity Feed
- Fetch feed from server
- Display feed items
- Filter by friends/clubs

### Phase 5: Clubs
- Club data model
- Polo notes list fetching
- Club membership detection
- Club filter in feed

### Phase 6: Sharing
- Share card SwiftUI templates
- Image rendering
- iOS share sheet integration
- Summary card generation

---

## Decisions

| Question | Decision |
|----------|----------|
| DX distance threshold | 5000km |
| Streak types | Daily QSOs and POTA daily |
| Feed pagination | TBD during implementation |
| Polo notes list format | TBD - need to confirm with Ham2K |
| Activity retention | TBD during implementation |

---

## Dependencies

- Challenges server modifications
- Ham2K Polo callsign notes API access
- Push notification infrastructure (optional, for friend requests)
