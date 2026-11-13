# Investigation: Memory Crashes on iPhone 11 (4GB RAM)

**Date:** 2026-03-12
**Status:** Resolved
**Outcome:** Multiple crash sites identified — startup caches, POTA sync arrays, and dashboard 100k QSO fetches

## Problem Statement

App crashes on iPhone 11 (4GB RAM) during both startup and POTA sync. Need to ensure both paths can run within the memory constraints of a 4GB device where iOS and SwiftUI consume ~1.5-2GB, leaving ~2GB for the app.

## Analysis

### Crash Site 1: App Startup — Concurrent Cache Loading

**File:** `CarrierWave/CarrierWaveApp.swift:162-171`

Four large caches load concurrently via `async let`:

| Cache | Data Structure | Est. Peak Memory |
|-------|---------------|-----------------|
| POTAParksCache | ~20K parks dict + name index | 30-50 MB |
| SOTASummitsCache | ~30K summits dict + name index | 20-40 MB |
| WWFFReferencesCache | ~35K references dict + name index | 40-60 MB |
| CallsignNotesCache | JSON download + merge | 10-20 MB |
| **TOTAL CONCURRENT** | | **100-170 MB** |

Each cache also does `String(contentsOf:)` loading the entire CSV into memory, then `csv.components(separatedBy: .newlines)` which creates a second copy as an array of strings, then iterates to build a dictionary. Peak during parsing is roughly 3x the file size.

Additionally, `SCPService.loadUserCallsigns()` (line 159) fetches ALL QSOs into memory just to count repeat callsigns — no `fetchLimit`, loads full QSO objects despite `propertiesToFetch`.

### Crash Site 2: POTA Sync — Unbounded Array Accumulation

**File:** `CarrierWave/Services/SyncService+SingleSync.swift:89-115`

Memory timeline during `syncPOTA()`:

1. `fetchAllQSOs()` accumulates ALL `POTAFetchedQSO` into `state.allFetched` (line 230 in POTAClient+Checkpoint.swift) — **unbounded growth**
2. Returns `(qsos, remoteMap)` — both held in memory
3. `let fetched = qsos.map { FetchedQSO.fromPOTA($0) }` (line 105) — creates SECOND large array while first still alive
4. Both `qsos` and `fetched` exist simultaneously: **2x the QSO data**
5. `potaRemoteQSOMap = remoteMap` (line 104) — stored as instance property, never cleared

For a user with 5,000+ POTA QSOs:
- `POTAFetchedQSO` array: ~50-100 MB (11 fields × ~200 bytes × 5K)
- `FetchedQSO` array: ~100-200 MB (25+ fields × ~400 bytes × 5K)
- `remoteQSOMap`: ~10-30 MB
- Peak during map phase: **160-330 MB**

## Fixes Applied

### Fix 1: Serialize cache loading (startup)
Load caches sequentially instead of concurrently. Reduces peak from ~170MB to ~60MB (one cache at a time). Startup takes slightly longer but avoids OOM.

### Fix 2: Use fetchCount for SCP repeat callsigns (startup)
Replace full QSO fetch with batched approach using `propertiesToFetch` properly, or use `fetchCount` with per-callsign predicates where feasible. Actually, SwiftData `propertiesToFetch` still materializes full objects — the real fix is to process in batches and release each batch.

### Fix 3: Release intermediate arrays between POTA sync phases
Wrap the download+convert in a scope so `qsos` is released before `fetched` is used. Use a local scope block to ensure the `POTAFetchedQSO` array is deallocated after conversion.

### Fix 4: Clear potaRemoteQSOMap after reconciliation
Set `potaRemoteQSOMap = nil` after `reconcileAndRepairPOTA` completes, freeing 10-30MB.

### Fix 5: Stream CSV parsing
Replace `csv.components(separatedBy: .newlines)` with line-by-line enumeration using `enumerateLines()` to avoid allocating the full array of lines.

### Crash Site 3: Dashboard — Unbounded QSO Fetches (100k QSOs)

**StatsComputationActor** (`StatsComputationActor.swift:250`):
- `FetchDescriptor<QSO>(predicate: ...)` with NO fetchLimit
- At 100k QSOs × ~3 KB per materialized object = ~300 MB
- Then converts to snapshots while holding all QSOs = ~500 MB peak

**NeedsEngine** (`NeedsEngine.swift:378-414`):
- 5 separate unbounded QSO fetches (fetchLimit=500k):
  - `fetchAllQSOs` × 2 (DXCC + WWFF): ~300 MB each
  - `fetchUSQSOs`: ~300 MB
  - `fetchHunterQSOs`: ~50-100 MB
  - `fetchActivatorQSOs`: ~20-50 MB
- All on the same ModelContext with no `.reset()` — context holds entire table
- Estimated peak: ~300-600 MB

StatsComputationActor and NeedsEngine fire **concurrently** from separate `.task(id:)` modifiers.
Combined worst case: ~800-1200 MB just from dashboard computation.

### Fix 6: Batch StatsComputationActor (dashboard)
Fetch QSOs in batches of 2,000 with `context.reset()` between batches. Converts to lightweight snapshots inline. Peak QSO memory drops from ~300 MB to ~6 MB per batch; accumulated snapshots ~12 MB.

### Fix 7: Single-pass batched NeedsEngine (dashboard)
Replace 5 separate unbounded fetches with a single batched pass (2,000 QSOs at a time, `context.reset()` between batches). Accumulates all needs data (DXCC, WAS, POTA, WWFF) simultaneously into lightweight sets/dicts. Peak QSO memory drops from ~300-600 MB to ~6 MB per batch; accumulated data ~12 MB.

## Follow-up: 2026-03-14

Three latent issues found during review of remaining memory pressure:

### Crash Site 4: BragSheetComputationActor — Unbounded QSO Fetch

**File:** `BragSheetComputationActor.swift:294-330`

Same pattern as the original StatsComputationActor bug (Fix #6) but the fix was never applied here. `fetchSnapshots()` loads ALL QSOs without `fetchLimit` or batching. For 100K QSOs = ~300 MB, and it fires **concurrently** with StatsComputationActor from `DashboardView.swift` `.task(id: hasLoadedDashboard)`.

### Fix 8: Batch BragSheetComputationActor (dashboard)
Applied the same 2,000-batch pattern from StatsComputationActor: fresh `ModelContext` per batch, `fetchLimit = 2_000`, `fetchOffset` iteration. Peak QSO memory drops from ~300 MB to ~5 MB per batch.

### Fix 9: Eliminate NeedsAccumulator.callsignBands array
The original single-pass NeedsEngine deferred DXCC processing by storing a `CallsignBandEntry` for every QSO in an array. For 100K QSOs × ~80 bytes = ~8 MB held until finalization.

Replaced with per-grid-prefix `PerGridDXCC` struct that accumulates DXCC entity sets inline during iteration. Most users operate from 1-3 grid squares, so this stores a few sets instead of 100K array entries.

### Fix 10: Release BragSheet cachedSnapshots after computation
`AsyncBragSheetStats` held `cachedSnapshots: [BragSheetQSOSnapshot]?` permanently for instant config changes. For 100K QSOs × ~250 bytes = ~25 MB held indefinitely in memory. Released the cache after all three periods are computed. Config changes now re-fetch from SwiftData using the batched path.

### Crash Site 5: One-Time Repair Jobs — Unbounded QSO Fetches

When a user gets sync working for the first time, ALL repair jobs fire on first dashboard
load with a freshly-synced large database. Three repair services loaded the entire QSO
table without batching:

| Service | Context | Est. Memory (5K QSOs) |
|---------|---------|----------------------|
| DeduplicationService | **Main thread** | ~50 MB |
| TwoferDuplicateRepairService | Background | ~50 MB |
| PhoneSSBDuplicateRepairService | Background | ~50 MB |
| ServicePresenceDeduplicationRepairService | Background | ~20 MB |

These run **sequentially** but share the same process memory with the concurrent
BragSheet/Stats/Needs computations that fire from the same `.task(id:)`.

### Fix 11: Batch DeduplicationService (off main thread)
Converted from `@MainActor final class` → `actor`. Batched fetch into lightweight
`QSOSnapshot` structs (2K per batch, ~5 MB peak). Dedup matching runs on snapshots,
then only affected QSOs are fetched by ID for merge. Peak memory drops from ~300 MB
to ~15 MB snapshots + ~5 MB per merge batch.

### Fix 12: Batch TwoferDuplicateRepairService
Same batch-to-snapshot pattern. `TwoferMatcher` already works on snapshots.

### Fix 13: Batch PhoneSSBDuplicateRepairService
Batch-fetch with inline PHONE/SSB filtering into minimal snapshots (6 fields vs full
QSO). Matching runs on snapshots; merge fetches only affected QSOs by ID.

### Fix 14: Batch ServicePresenceDeduplicationRepairService
Batch-fetch ServicePresence into lightweight snapshot structs. Grouping and dedup
selection on snapshots, then batch-delete by PersistentIdentifier.

### Combined Impact

| Fix | Before | After |
|-----|--------|-------|
| BragSheet fetch | ~300 MB unbounded | ~5 MB per 2K batch |
| NeedsEngine callsignBands | ~8 MB (100K entries) | ~1 MB (few set operations) |
| BragSheet cachedSnapshots | ~25 MB permanent | Released after computation |
| DeduplicationService | ~300 MB on main thread | ~15 MB snapshots (background) |
| TwoferDuplicateRepairService | ~300 MB unbounded | ~15 MB snapshots |
| PhoneSSBDuplicateRepairService | ~300 MB unbounded | ~5 MB snapshots |
| ServicePresenceDedup | ~100 MB unbounded | ~10 MB snapshots |
| **Total worst-case savings** | **~1.3 GB** | **~56 MB** |

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `CarrierWaveApp.swift` | App entry point | 4 caches load concurrently at line 162-171 |
| `POTAParksCache.swift` | Parks cache | Full CSV string load + components array + dict + name index |
| `SOTASummitsCache.swift` | Summits cache | Same pattern as parks |
| `WWFFReferencesCache.swift` | WWFF cache | Same pattern, largest dataset |
| `SCPService.swift` | SCP callsigns | Fetches ALL QSOs without limit at line 100 |
| `SyncService+SingleSync.swift` | POTA sync | Two large arrays held simultaneously at lines 89-105 |
| `POTAClient+Checkpoint.swift` | POTA download | `allFetched` grows unbounded at line 230 |
| `POTAClient+Adaptive.swift` | Download state | `POTADownloadState.allFetched` is the accumulator |
| `SyncService.swift` | Sync service | `potaRemoteQSOMap` persists as instance property (line 64) |
| `StatsComputationActor.swift` | Dashboard stats | Unbounded QSO fetch, no fetchLimit, holds all + snapshots |
| `NeedsEngine.swift` | Dashboard needs | 5 separate unbounded fetches, no context.reset() |
| `DashboardView.swift` | Dashboard | Stats + Needs fire concurrently from `.task(id:)` |
| `BragSheetComputationActor.swift` | Brag sheet | Unbounded QSO fetch, same bug as StatsComputationActor |
| `AsyncBragSheetStats.swift` | Brag sheet | cachedSnapshots held permanently (~25 MB) |
| `DeduplicationService.swift` | QSO dedup repair | Unbounded fetch on main thread |
| `TwoferDuplicateRepairService.swift` | Two-fer dedup | Unbounded QSO fetch |
| `PhoneSSBDuplicateRepairService.swift` | PHONE/SSB dedup | Unbounded QSO fetch |
| `ServicePresenceDeduplicationRepairService.swift` | Presence dedup | Unbounded ServicePresence fetch |
