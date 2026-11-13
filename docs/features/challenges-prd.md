# Challenges Feature - Product Requirements Document

## Overview

Challenges enable Carrier Wave users to track progress toward ham radio activities and awards (DXCC, WAS, POTA, etc.) with optional social/competitive elements including leaderboards and time-limited competitions.

## Problem Statement

Amateur radio operators pursue various awards and personal goals (DXCC, Worked All States, POTA activator/hunter milestones), but tracking progress is fragmented across multiple websites, spreadsheets, and manual record-keeping. There's no unified way to:

- Track progress toward multiple goals in one place
- Participate in community challenges with leaderboards
- Get automated assistance (spotting alerts) for completing goals
- Create and share custom challenges

## User Value

- **Unified tracking**: See progress toward all active challenges in one app
- **Motivation**: Leaderboards and badges encourage continued participation
- **Discovery**: Find new challenges created by the community
- **Automation**: HamAlert integration creates/removes spots for needed entities
- **Social**: Join challenges with friends, clubs, or the global community

---

## User Personas

### Official Curator
Maintains the official challenge source with well-tested, high-quality challenge definitions for major awards (DXCC, WAS, WAC, POTA milestones, etc.).

### Community Author
Creates and hosts challenge definitions for clubs, special events, or niche interests. Distributes via their own server or shared hosting. May create invite-link challenges for specific groups.

### Participant
Joins challenges to track personal progress. May participate in solo challenges (just tracking) or competitive challenges (leaderboards). Uses the app to log QSOs and see progress update in real-time.

---

## User Stories

### Challenge Discovery & Joining

- As a participant, I can browse challenges from the official source so I can find major awards to track.
- As a participant, I can add community source URLs so I can access club or special-event challenges.
- As a participant, I can join a challenge via invite link so I can participate in a specific group competition.
- As a participant, I can see challenge details (description, rules, scoring, time limits) before joining.
- As a participant, I can join challenges for solo tracking without leaderboard participation.

### Progress Tracking

- As a participant, I see my progress (percentage, items completed, points) for each active challenge.
- As a participant, I can drill down into a challenge to see what I've completed and what remains.
- As a participant, my progress updates in real-time as I log QSOs.
- As a participant, I receive in-app notifications when I make progress ("You just worked Alaska - 3 states remaining!").
- As a participant, I can configure whether my historical QSOs count toward a challenge (if the challenge allows it).

### Leaderboards & Competition

- As a participant, I can view the leaderboard for any challenge I've joined.
- As a participant, I see callsigns and scores for all participants on leaderboards.
- As a participant, leaderboard positions update in real-time.
- As a participant in a time-limited challenge, I can see the countdown to challenge end.

### Challenge Completion & Lifecycle

- As a participant, I earn badges when completing challenge tiers or the full challenge.
- As a participant, I can view historical challenges I've completed, including frozen final standings.
- As a participant, I can leave a challenge, which removes my data from leaderboards.
- As a participant, I understand that challenge goals may update (e.g., new DXCC entity) and affect my completion status.

### HamAlert Integration

- As a participant, I can enable HamAlert integration for a challenge.
- As a participant, alerts are automatically created for entities/parks/states I still need.
- As a participant, alerts are automatically removed when I work a needed entity.

### Challenge Authoring (Configurator - Separate Web Tool)

- As an author, I can create collection-based challenges (work all items from a list).
- As an author, I can create cumulative challenges (reach N contacts/points).
- As an author, I can create time-bounded challenges (calendar dates or relative duration).
- As an author, I can define qualification criteria: bands, modes, special fields (park ref, SOTA ref, grid), date ranges.
- As an author, I can configure scoring rules for leaderboard ranking.
- As an author, I can define tiers/levels within a challenge.
- As an author, I can upload badges for tier/completion achievements.
- As an author, I can specify whether historical QSOs are allowed.
- As an author, I can generate invite links that track participants.
- As an author, I can publish challenges to my own server for community distribution.

---

## Challenge Types

### Collection-Based
Track progress toward completing a defined set of entities.

**Examples:**
- Worked All States (50 states)
- DXCC (100+ entities)
- Worked All Continents (6 continents)
- US Counties (3,077 counties)

**Progress model:** X of Y completed (e.g., "47/50 states")

### Cumulative/Numeric
Track progress toward a numeric goal.

**Examples:**
- POTA Hunter: 1000 park contacts
- POTA Kilos: 66 activator points
- QSO count milestones

**Progress model:** Current value / target (e.g., "847/1000 contacts")

### Time-Bounded
Challenges with defined start/end dates, often for special events.

**Examples:**
- 13 Colonies (July 1-7)
- Field Day (4th weekend in June)
- Club sprint: "Most CW contacts this month"

**Time specification:**
- Calendar dates (start/end)
- Relative duration ("2 weeks from join date")

### Tiers
Any challenge type can have multiple tiers representing milestones.

**Example (DXCC):**
- DXCC: 100 entities
- DXCC 200: 200 entities
- DXCC 300: 300 entities
- ...
- DXCC Honor Roll: 331+ entities

---

## Qualification Criteria

QSOs qualify for a challenge based on configurable criteria:

| Criterion | Description | Example |
|-----------|-------------|---------|
| **Band** | Restrict to specific bands | "40m and 20m only" |
| **Mode** | Restrict to specific modes | "CW only", "Digital modes" |
| **Special fields** | Require specific QSO fields | POTA park reference, SOTA reference, grid square |
| **Date range** | QSO must fall within dates | "January 1-31, 2025" |
| **Historical QSOs** | Allow/forbid QSOs logged before joining | Configurable per challenge |

**Note:** Confirmation requirements (LoTW, QSL) are out of scope for v1.

---

## Scoring & Leaderboards

### Scoring Configuration
Challenge authors define how participants are ranked:

- **Completion percentage** (default for collection challenges)
- **Raw count** (items completed or contacts made)
- **Points** (weighted scoring, e.g., DX = more points)
- **Custom formulas** (TBD - may be v2)

### Leaderboard Display
- Participant callsigns
- Score/progress
- Rank
- Real-time updates

### Time-Limited Challenge End
- Final standings frozen as snapshot
- Historical view preserved
- Badges awarded based on final standing/completion

---

## Distribution Architecture

### Sources

| Source Type | Trust Level | Management |
|-------------|-------------|------------|
| **Official** | Trusted | Hosted by Carrier Wave, curated quality |
| **Community** | User-added | Users add URLs to community sources |
| **Invite Link** | Implicit trust | Join specific challenge via link |

### API Requirements
- Open, documented API specification
- JSON-based challenge definitions
- Versioning for challenge updates
- Multiple community source URLs supported in app

### Challenge Updates
- Entity lists may change (new DXCC entity, new parks)
- App fetches updated definitions
- User progress recalculated against new goals
- Completion status may change (acceptable)

---

## App Integration

### Sync Destination
Challenges sync is an optional sync destination alongside QRZ, POTA, LoFi:
- User enables/disables challenge sync
- Per-challenge participation configuration
- Progress synced to challenge server for leaderboards

### UI Placement
- **Challenges tab**: Dedicated tab for challenge management
  - Browse/join challenges
  - View active challenge progress
  - Leaderboards
  - Historical/completed challenges
- **In-app notifications**: Progress alerts as QSOs are logged

### HamAlert Integration
- OAuth or API key connection to HamAlert
- Automatic alert creation for needed entities
- Automatic alert deletion on progress
- Configurable per-challenge

---

## Success Metrics

- Number of users with at least one active challenge
- Challenge completion rates
- Leaderboard participation (challenges with 2+ participants)
- Community source adoption (users adding non-official sources)
- HamAlert integration usage
- Retention impact (users with challenges vs. without)

---

## Scope

### In Scope (v1)
- All three challenge types (collection, cumulative, time-bounded)
- Tiers within challenges
- All qualification criteria (band, mode, special fields, date range, historical toggle)
- Official + community sources
- Invite links with participant tracking
- Leaderboards with real-time updates
- Badges (uploadable in configurator)
- HamAlert integration
- In-app notifications
- Challenge sync as optional destination
- Web-based configurator (separate repository)

### Out of Scope (v1)
- Confirmation requirements (LoTW, QSL card verification)
- Other spotting integrations (POTA Spotting API, SOTAwatch, DXCluster)
- Anonymous participation
- Custom scoring formulas (basic options only)
- In-app challenge authoring (web configurator only)

---

## Design Decisions

1. **Offline behavior**: Connectivity required for challenge features. Progress is not cached offline.

2. **Invite link controls**: Expiration and max participant limits are configurable per-challenge in the configurator.

## Open Questions

1. **Conflict resolution**: If a QSO qualifies for multiple challenges, any special handling needed?

2. **Rate limiting**: For real-time leaderboard updates, what's the acceptable refresh rate?

3. **Badge format**: What image formats/sizes for uploadable badges?

---

## Appendix: Example Challenges

### DXCC (Collection + Tiers)
```
Type: Collection
Goal: Work 100+ DXCC entities
Tiers: 100, 200, 300, 400, 500, Honor Roll (331+)
Criteria: Any band, any mode
Historical: Allowed
Scoring: Entity count
```

### Worked All States (Collection)
```
Type: Collection
Goal: Work all 50 US states
Criteria: Any band, any mode
Historical: Allowed
Scoring: State count
```

### POTA Kilo Challenge (Cumulative)
```
Type: Cumulative
Goal: Earn 66 activator points (Kilo)
Criteria: Valid POTA activations (10+ QSOs per park)
Historical: Allowed
Scoring: Point total
```

### Club January Sprint (Time-Bounded + Cumulative)
```
Type: Cumulative, Time-bounded
Goal: Most CW QSOs in January
Dates: January 1-31, 2025
Criteria: CW mode only
Historical: Not allowed
Scoring: QSO count
```
