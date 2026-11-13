# Club Integration Enhancements Design

**Date:** 2026-03-03

## Goal

Deepen club integration across the app by surfacing club membership prominently in spot lists, logging, and session summaries. Currently clubs show only a small blue icon on spot rows — this design adds grouping, filtering, and contextual badges.

## Design Decisions

- **Grouping style:** Section headers ("Club Members" / "Other Spots"), not inline sort
- **Club names:** Shown on each row as a secondary label (e.g. "BVARC, LAARC"), not in section header
- **POTA spots:** Club section above band groups, club member spots removed from band sections to avoid duplicates
- **Deduplication:** A callsign in multiple clubs appears once in the club section with all club names listed

## Features

### 1. Hunter Log — Club-First Grouping

**Files:** `ActivityLogSpotsList.swift`, `ActivityLogSpotRow.swift`

After dedup + sort, partition spots into club members vs. others using `ClubsSyncService.shared.clubs(for:)`.

- "Club Members" section header, then club member rows with club name tags
- "Other Spots" section header, then remaining rows
- Within each section, maintain existing sort order (recent or frequency)
- "Other Spots" header only rendered when club section is non-empty
- Club names shown as secondary text on each club member row

### 2. Session Spots — Club-First Grouping

**File:** `SessionSpotsSection.swift`

Same partition logic applied to persisted session spots.

- Club member spots in a "Club Members" section at top
- RBN run collapsing still applies in the "Other Spots" section
- Club member RBN spots shown individually to surface them
- Club names on rows

### 3. POTA Spots — Club Section Above Bands

**Files:** `POTASpotsView.swift`, `SidebarPOTASpotsView.swift`

- Extract club member spots into a "Club Members" section at top, with band label on each row
- Remove those spots from band groups to prevent duplicates
- When club filter is active, only the club section shows

### 4. Club Filter Chip

**Files:** `SpotFilters.swift` (or equivalent), `ActivityLogSpotsList.swift`, `POTASpotsView.swift`

- New "Club" toggle alongside existing filter chips (band, mode, region, etc.)
- When active, filters to only spots where callsign is in `clubMemberCallsigns`
- Hidden if user has no clubs

### 5. QSO Logging Badge

**File:** Logging view callsign field area

- When callsign field value matches a club member, show a club badge
- Similar styling to worked-before badge
- Shows club name(s) for context before logging

### 6. Session Summary Card

**File:** `SessionDetailView.swift`

- After session ends, show card: "You worked N club members this session"
- Lists callsigns and their clubs
- Only shown when N > 0

## Data Layer

All features use `ClubsSyncService.shared` which provides:

- `clubs(for callsign: String) -> [String]` — O(1) lookup, returns club names
- `clubMemberCallsigns: Set<String>` — O(1) membership check
- `clubsByCallsign: [String: [String]]` — full map

No new models or persistence changes needed. All club data is already cached in memory.
