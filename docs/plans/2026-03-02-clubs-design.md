# Clubs Feature Design (CAR-108)

## Overview

Add club support to Carrier Wave so ham radio clubs can see members' activity, status, and proximity. Clubs are server-admin created, admin-managed rosters with a purely social focus (no challenges/leaderboards).

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Membership model | Admin-managed roster by callsign | Mirrors real ham clubs; secretary maintains roster |
| Club creation | Server admin only | Prevents spam, keeps it controlled |
| Multi-club | Yes | Hams belong to multiple clubs in real life |
| Location data | Grid square from QSOs | Privacy-friendly, already in the data |
| Online status | RBN spots + app last-seen combined | Best picture of who's active |
| Club challenges | No (purely social) | Keep clubs and challenges as separate systems |
| Architecture | Thin server + rich client | Server provides data, iOS does the heavy lifting for UI |
| Local storage | SwiftData | Offline access required |

## Server Data Model

### New Tables

```sql
CREATE TABLE clubs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    callsign TEXT,              -- club's own callsign, if any
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE club_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    club_id UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
    callsign TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'member',  -- 'admin' | 'member'
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(club_id, callsign)
);

CREATE INDEX idx_club_members_callsign ON club_members(callsign);
CREATE INDEX idx_club_members_club_id ON club_members(club_id);
```

### API Endpoints

#### Admin (ADMIN_TOKEN required)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/v1/admin/clubs` | Create club (name, callsign, description) |
| `PUT` | `/v1/admin/clubs/:id` | Update club metadata |
| `DELETE` | `/v1/admin/clubs/:id` | Delete club (cascades members) |
| `POST` | `/v1/admin/clubs/:id/members` | Add member(s) by callsign with role |
| `DELETE` | `/v1/admin/clubs/:id/members/:callsign` | Remove member |
| `PUT` | `/v1/admin/clubs/:id/members/:callsign` | Change member role |

#### Authenticated (Bearer token required)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/v1/clubs` | List clubs the authenticated user belongs to |
| `GET` | `/v1/clubs/:id` | Club detail + full member list with last-seen and grid |
| `GET` | `/v1/clubs/:id/activity` | Club activity feed (paginated, cursor-based) |
| `GET` | `/v1/clubs/:id/status` | Member online/active status |

#### Response Enrichment

`GET /v1/clubs/:id` enriches each member with:
- `last_seen_at` from `participants` table
- `last_grid` from most recent activity/QSO data
- `callsign` and `role`

`GET /v1/clubs/:id/status` returns per-member status:
- `on_air` — callsign found in recent RBN/cluster spots
- `recently_active` — `last_seen_at` within threshold (e.g., 15 minutes)
- `inactive` — neither condition met

## iOS Data Model

### SwiftData Models

```swift
@Model
final class Club {
    var serverId: UUID
    var name: String
    var callsign: String?
    var clubDescription: String?
    var lastSyncedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ClubMember.club)
    var members: [ClubMember]
}

@Model
final class ClubMember {
    var callsign: String
    var role: String          // "admin" | "member"
    var lastSeenAt: Date?
    var lastGrid: String?
    var club: Club
}
```

### Sync Strategy

- **ClubSyncService** (background actor) — fetches clubs + members from server, reconciles into SwiftData
- Runs on: app launch, foreground resume, periodic interval (~5 minutes)
- Full-replace per club — server is source of truth, replace member list entirely on each sync
- **In-memory callsign set** (`Set<String>`) derived from SwiftData after sync for O(1) logger lookups
- Status data (on-air/recently-active) is NOT persisted — fetched live when viewing club detail

## iOS UI Surfaces

### 1. Club Hub (More tab section)

- List of user's clubs with member count and recent activity summary
- Tap into club detail with three sections:
  - **Members** — list with status indicators (green dot = on-air, yellow = recently active, grey = inactive)
  - **Activity** — club-scoped activity feed (recent QSOs, milestones from members)
  - **Map** — member pins at last-known grid square, colored by status

### 2. Logger Integration

- When entering a callsign, if it matches a club member: show badge "CLUB: [Club Name]" near the callsign field
- After logging a QSO with a club member: celebratory moment in confirmation ("Worked club member [callsign]!")
- Multiple clubs shown if member is in more than one shared club

### 3. QSO Detail

- Club badge(s) on QSO detail view if the worked station is a club member
- Retroactive discovery: "I worked someone from my club"

### 4. Activity Feed Enhancement

- Club member activities in the existing feed get a club badge/tag
- "This person is also in [Club Name]"

### 5. Club Stats Dashboard (inside club detail)

- Total club QSOs this week/month
- Most active member
- Bands/modes breakdown across the club
- Grid squares covered by the club (aggregate map coverage)
- Computed locally from activity feed data + cached member info

### 6. Spots Integration

- RBN/cluster spots from/of a club member highlighted with club indicator
- "Your club member K1ABC was just spotted on 20m CW"

## Data Flow

```
Server (source of truth)
  └─ clubs + members
       └─ ClubSyncService (periodic fetch)
            └─ SwiftData (offline persistence)
                 ├─ ClubManager (in-memory callsign set)
                 │    └─ Logger callsign matching
                 ├─ Club Hub screens
                 ├─ QSO detail badges
                 └─ Spot highlighting

Server (live only, not persisted)
  └─ /clubs/:id/status
       └─ Club detail screen (on-air/active indicators)
```

## Out of Scope

- Push notifications for club member activity
- Club chat/messaging
- Club-specific challenges/leaderboards
- Club-to-club comparisons
- Self-join or invite links (admin-managed only)
