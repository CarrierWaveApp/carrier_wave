# QSO Deduplication Feature Design

## Overview

Add a manual deduplication feature to Settings that finds and auto-merges similar QSOs based on configurable time-delta matching, with a summary of actions taken.

## Problem

Current deduplication uses 2-minute bucket rounding which misses near-duplicates that cross bucket boundaries. Users are seeing inflated QSO counts from:
- Same contact imported from multiple services with slight time drift
- Time bucket boundary edge cases (14:29:59 vs 14:30:01)

## Matching Algorithm

**Duplicate detection criteria:**
- Callsign matches (case-insensitive)
- Band matches (case-insensitive)
- Mode matches (case-insensitive)
- Time delta < configurable threshold (default: 5 minutes)

**Algorithm:**
1. Sort all QSOs by timestamp
2. For each QSO, compare against subsequent QSOs within the time window
3. Group matches into "duplicate clusters"

**Configuration:**
- `dedupeTimeWindowMinutes: Int` stored in UserDefaults
- Exposed in Settings UI with stepper (1-15 minutes, default 5)

## Merge Strategy

**Winner selection (in priority order):**
1. Prefer QSO with ServicePresence records marked `isPresent = true` (already confirmed in QRZ/POTA/LoFi)
2. If tied: keep QSO with more non-nil fields populated

**Field richness scoring** - count populated fields:
- `rstSent`, `rstReceived`
- `gridSquare`, `myGridSquare`
- `parkReference`, `myParkReference`
- `qrzLogId`, `potaQsoId`
- `rawADIF`

**Merge behavior:**
- Winner absorbs any ServicePresence records from losers
- Winner fills in any nil fields from loser if loser has them
- Losers are deleted from SwiftData

## UI Design

**Settings placement:**
- New section: "Deduplication"
- Contains:
  - Stepper: "Time window: X minutes" (1-15, default 5)
  - Button: "Find & Merge Duplicates"

**Flow when button tapped:**
1. Show progress indicator ("Scanning QSOs...")
2. Run deduplication algorithm
3. Display summary alert:
   - "Found X duplicate groups. Merged Y QSOs, removed Z duplicates."
   - Or "No duplicates found" if clean

## Implementation Structure

**New file: `DeduplicationService.swift`**
```swift
actor DeduplicationService {
    func findAndMergeDuplicates(
        context: ModelContext,
        timeWindowMinutes: Int = 5
    ) async throws -> DeduplicationResult
}

struct DeduplicationResult {
    let duplicateGroupsFound: Int
    let qsosMerged: Int      // winners that absorbed data
    let qsosRemoved: Int     // losers deleted
}
```

**Modified: `SettingsView.swift`**
- Add "Deduplication" section with stepper and button
- Handle async operation with progress state

**Modified: `QSO.swift`**
- Add `fieldRichnessScore: Int` computed property

**Unchanged:**
- ImportService (keeps existing dedup key for import-time)
- SyncService
