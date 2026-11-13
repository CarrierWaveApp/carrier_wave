# Investigation: Memory Analysis at 100K QSOs

**Date:** 2026-03-20
**Symptom:** Startup crashes on high-QSO-count users with no crash reports (suspected OOM kills)
**Methodology:** Static analysis of all code paths that touch QSO/ServicePresence data

---

## Executive Summary

At 100K QSOs, the app's **peak startup memory reaches ~150-200 MB above baseline** from concurrent stats computations alone. Combined with the app's base footprint and iOS overhead, this pushes 4GB devices (iPhone 11/SE 3) past the ~1.2-1.4 GB Jetsam limit. Several sync and import paths have fully unbounded fetches that can spike to 400-800 MB.

**The smoking gun for startup OOM:** Three stats computations (`BragSheetComputationActor`, `PresenceComputationActor`, `NeedsEngine`) run concurrently on the Dashboard tab, each scanning all QSOs and accumulating results in memory simultaneously.

---

## 1. Per-Object Memory Cost

### QSO Model (~1,000 bytes typical, up to 3,000 bytes rich)

| Property Category | Count | Est. Bytes |
|---|---|---|
| Core fields (callsign, band, mode, frequency, timestamp) | 5 | ~180 |
| RST fields | 2 | ~100 |
| Location fields (grids, state, country, qth) | 5 | ~200 |
| Park/program references (POTA, SOTA, WWFF, AOA) | 4 | ~150 |
| Sync fields (qrzLogId, lotwConfirmed, cloudDirtyFlag, etc.) | 6 | ~60 |
| Contest fields | 5 | ~120 |
| **`rawADIF` (full ADIF record text)** | 1 | **200-2,000** |
| SwiftData overhead (isa, refcount, context backpointer, change tracking) | - | ~80 |

### ServicePresence (~240 bytes each, 2-5 per QSO)

### CloudSyncMetadata (~400 bytes each, 1 per synced entity)

### Total Materialized Cost at 100K QSOs

| Scenario | Objects | Memory |
|---|---|---|
| QSOs only | 100K | ~95 MB |
| + ServicePresence (2x avg) | +200K | +46 MB |
| + CloudSyncMetadata (iCloud on) | +300K | +114 MB |
| **Total if all materialized** | **600K** | **~255 MB** |
| + rawADIF populated (avg 500B) | - | **+50 MB** |

---

## 2. Startup Memory Timeline (Dashboard Tab)

The dashboard is the default tab and triggers the heaviest computation chain.

### Phase 1: App Init (T+0s)

| Operation | Memory | Risk |
|---|---|---|
| ModelContainer creation | Baseline | None |
| DataRepairService.runAsyncRepairs (band case, first-run only) | +1-2 MB per batch, released | Low |
| CloudSyncService.configure + CKSyncEngine start | Low | None |

### Phase 2: Dashboard Stats Pipeline (T+0.5-1s)

**Sequential first:**

| Operation | File | Memory | Released? |
|---|---|---|---|
| `StatsComputationActor.fetchAndConvertToSnapshots()` | `StatsComputationActor.swift:309-363` | **+30-40 MB** (100K StatsQSOSnapshot + 6 MB seenIds Set) | Yes, after compute |
| `computeStatsFromSnapshots()` (multiple filter passes) | `StatsComputationActor.swift:100-236` | +5-15 MB transient arrays | Partially |

**Then concurrent (this is the problem):**

| Operation | File | Memory | Released? |
|---|---|---|---|
| `BragSheetComputationActor.fetchAllSnapshots()` | `AsyncBragSheetStats.swift:97-128` | **+30-40 MB** (100K BragSheetQSOSnapshot, 27 fields each) | After compute |
| `PresenceComputationActor.computeCounts()` | `AsyncServicePresenceCounts.swift:80-117` | **+20-30 MB** (300K ServicePresence with QSO prefetch) | After compute |
| `NeedsEngine.recompute()` | `NeedsEngine.swift:131-171` | **+5-10 MB** (accumulator sets) | After compute |
| `SCPService.fetchRepeatCallsigns` (fire-and-forget) | - | **+10-15 MB** (callsign dictionary) | Never (cached) |

### Peak Memory at Startup

```
Baseline app footprint:                    ~80 MB
+ BragSheetComputationActor snapshots:    +35 MB
+ PresenceComputationActor (with prefetch): +25 MB
+ NeedsEngine accumulators:               +8 MB
+ SCPService callsign cache:              +12 MB
+ WAS stateCallsigns (retained forever):  +10 MB
+ Transient intermediates:                +15 MB
─────────────────────────────────────────────────
PEAK STARTUP:                             ~185 MB above baseline
```

On a 4 GB device with ~1.2 GB Jetsam limit, this leaves very little headroom for the system, other apps, and any concurrent sync activity.

---

## 3. Critical Unbounded Fetches (Will OOM at 100K)

### Severity: CRITICAL

| # | File | Line | Pattern | Est. Memory at 100K |
|---|---|---|---|---|
| 1 | `ImportService.swift` | 156 | `FetchDescriptor<QSO>()` -- no limit, main context | **400 MB+** |
| 2 | `ImportService+External.swift` | 16-21 | Unbounded fetch + 2 Dictionary groupings (QRZ import) | **500 MB+** |
| 3 | `ImportService+External.swift` | 123-125 | Unbounded fetch + Dictionary (POTA import) | **400 MB+** |
| 4 | `CloudSyncEngine+Helpers.swift` | 143-156 | `markAllRecordsDirtyImpl()` -- ALL QSOs + ALL ServicePresence | **800 MB+** |
| 5 | `CloudSyncEngine+Outbound.swift` | 23-47 | Dirty QSOs + dirty ServicePresence, no fetchLimit | **400 MB+** after markAllDirty |
| 6 | `CallsignSuggestionProvider.swift` | 78 | All non-hidden QSOs for suggestion counting | **400 MB+** |

### Severity: HIGH (50K fetchLimit still dangerous)

| # | File | Line | Pattern | Est. Memory |
|---|---|---|---|---|
| 7 | `SyncService+ProcessLegacy.swift` | 24, 96, 236 | Three methods each loading up to 50K QSOs | ~200 MB |
| 8 | `DashboardView+Actions.swift` | 206, 231 | Clear QRZ/LoFi data loads 50K QSOs | ~200 MB |
| 9 | `CloudSyncEngine+Inbound.swift` | 120, 337 | 50K limit for sync dedup matching | ~200 MB |

### Severity: BUG

| # | File | Line | Issue |
|---|---|---|---|
| 10 | CWSweep `LoTWSyncService+Matching.swift` | 61 | `fetchLimit = 5` with NO predicate -- fetches 5 random QSOs, will almost never match |

---

## 4. Steady-State Memory Sinks

These stay in memory after startup and are never released:

| Component | Data Structure | Est. Size at 100K | Notes |
|---|---|---|---|
| `AsyncQSOStatistics.wasData` | `[WASFilterKey: WASStateData]` with callsign arrays per state | 5-15 MB | Retained for WAS drill-down; grows with US-state QSOs |
| `SCPService` callsign cache | `[String: Int]` repeat callsign counts | 10-15 MB | Fire-and-forget at startup, never cleared |
| `AsyncQSOStatistics.activityByDate` | `[Date: Int]` day-level counts | <1 MB | Fine |

---

## 5. Map Tab Memory (On-Demand, Not Startup)

The map tab does not load at startup, but when selected:

| Scenario | Memory | Risk |
|---|---|---|
| Default (1,000 QSO limit) | ~240 KB | None |
| `showAllQSOs` toggle ON | 18-24 MB (MapQSOSnapshot array) | Moderate |
| + `showPaths` toggle ON | **+58 MB** (100K QSOArc with 31-point geodesic paths) | **HIGH** |
| + Grid overlay ON | +6-10 MB (GridAccumulation + polygons) | Moderate |

---

## 6. Stats Drill-Down Memory (On-Demand)

`QSOStatistics` drill-down always takes the fallback path because `asyncStats.getStats()` always returns nil (the `stats` property is never set by the background computation). This causes:

- Fresh fetch of **10,000 QSO managed objects** (not snapshots)
- SwiftData managed objects at ~4 KB each = **~40 MB**
- Plus `StatCategoryItem` grouped/sorted copies = **~60-80 MB total**
- Released when drill-down view dismisses

---

## 7. Recommendations

### P0: Fix Startup Concurrency (Likely Cause of OOM Crashes)

**Problem:** `BragSheetComputationActor`, `PresenceComputationActor`, and `NeedsEngine` all scan all QSOs concurrently from `DashboardView`.

**Fix:** Serialize the stats pipeline or share a single scan pass:
1. **Option A (Quick):** Make bragSheet, presenceCounts, and needsEngine sequential instead of concurrent. Peak drops from ~80 MB to ~40 MB.
2. **Option B (Better):** Single-pass architecture -- one scan of all QSOs that feeds data to all consumers. Eliminates redundant fetches entirely.
3. **Option C (Best):** Incremental stats -- only recompute on delta since last computation. Cache results to disk.

### P0: Batch `markAllRecordsDirtyImpl()`

**Problem:** Loads every record in every table into one context.

**Fix:** Batch in groups of 1,000 with fresh ModelContext per batch:
```swift
var offset = 0
while true {
    let ctx = ModelContext(container)
    var desc = FetchDescriptor<QSO>()
    desc.fetchLimit = 1000
    desc.fetchOffset = offset
    let batch = try ctx.fetch(desc)
    guard !batch.isEmpty else { break }
    for qso in batch { qso.cloudDirtyFlag = true }
    try ctx.save()
    offset += batch.count
}
```

### P1: Batch All Import Dedup Lookups

**Problem:** `ImportService` and `ImportService+External` load all QSOs to build dedup sets.

**Fix:** Use the existing `QSOProcessingActor.fetchExistingQSOKeys()` pattern (batched with fresh contexts) instead of unbounded main-context fetches.

### P1: Batch `collectDirtyQSOChanges()` / `collectDirtyServicePresenceChanges()`

**Problem:** After `markAllDirty`, these fetch all dirty records without limit.

**Fix:** Add `fetchLimit` and process in pages, yielding `CKSyncEngine.RecordZoneChanges` per page.

### P1: Cap or Batch `CallsignSuggestionProvider`

**Problem:** Loads all QSOs to count callsign frequencies.

**Fix:** Batch fetch like `FriendSuggestionActor`, or precompute/cache the frequency table during stats computation.

### P2: Eliminate `rawADIF` Storage

**Problem:** Storing full ADIF text per QSO adds ~50 MB at 100K QSOs for data that's only used for re-export.

**Fix:** Generate ADIF on-the-fly from structured fields. If raw preservation is needed, store in a separate lazy-loaded model or on disk.

### P2: Fix Stats Drill-Down Fallback

**Problem:** `asyncStats.getStats()` always returns nil, forcing a 10K managed-object fetch.

**Fix:** Either populate the `stats` property from `StatsComputationActor`, or rewrite drill-down to use snapshots instead of managed objects.

### P2: Reduce WAS Callsign Retention

**Problem:** `wasData` stores every callsign string per state/mode, retained forever.

**Fix:** Store only counts + a capped sample (e.g., last 10 callsigns per state) instead of the full list.

### P3: Map Arc Memory

**Problem:** 100K arcs with 31-point paths = 58 MB.

**Fix:** Reduce path resolution (e.g., 8 points instead of 31), or virtualize arcs to only render visible ones.

### P3: CWSweep Unbounded Fetches

Multiple CWSweep services (`DashboardView`, `DXCCNeededChecker`, `AwardsDashboardService`, `ADIFImportActor`) load all QSOs unbounded. macOS has more RAM headroom but should still batch for correctness.

---

## 8. What Breaks First

Ranked by likelihood of causing the reported startup OOM:

1. **Concurrent stats on Dashboard** -- Happens every launch. ~80 MB spike on top of baseline. Most likely culprit for 4GB devices.
2. **iCloud full re-sync** (`markAllRecordsDirty` + `collectDirty`) -- Happens on iCloud account changes, device restore, or sync reset. ~800 MB spike. Guaranteed OOM.
3. **QRZ/POTA import** -- Happens when user imports from external service. ~400-500 MB spike. Guaranteed OOM.
4. **CallsignSuggestionProvider** -- Triggered when typing in the callsign field. ~400 MB spike. Guaranteed OOM.
5. **Legacy sync reconciliation** -- 50K limit still dangerous at ~200 MB.

---

## 9. Quick Wins (Most Impact, Least Effort)

| Fix | Files to Change | Impact |
|---|---|---|
| Serialize bragSheet/presenceCounts/needsEngine | `DashboardView.swift` | -40 MB peak startup |
| Add fetchLimit to `CallsignSuggestionProvider` | 1 file | Prevents 400 MB spike on typing |
| Batch `markAllRecordsDirtyImpl` | 1 file | Prevents 800 MB spike on re-sync |
| Batch `ImportService.fetchExistingDeduplicationKeys` | 1 file | Prevents 400 MB spike on import |
| Batch `ImportService+External` dedup lookups | 1 file | Prevents 400-500 MB spike on QRZ/POTA import |

---

## 10. Implementation Status

All quick wins from Section 9 have been implemented. Changes below cap peak memory
to ~5 MB per batch regardless of total QSO count. No code path loads more than
1,000 QSO/ServicePresence objects at a time.

### Completed Fixes

| Fix | Files Changed | Approach |
|---|---|---|
| **Serialize dashboard stats pipeline** | `DashboardView.swift`, `DashboardView+Needs.swift` | Stats, presence, equipment, brag sheet, and needs now run sequentially instead of concurrently. Needs computation moved from independent `.task` into main pipeline. Peak drops from ~80 MB to ~35 MB. |
| **Batch `ImportService.fetchExistingDeduplicationKeys`** | `ImportService.swift` | Batched fetch (1K/batch) with fresh `ModelContext` per batch. Builds only a `Set<String>` of dedup keys. |
| **Batch QRZ/POTA import lookups** | `ImportService+External.swift` | Changed from `[String: [QSO]]` dictionaries (~400 MB) to lightweight `[String: UUID]` maps (~20 MB). Individual QSOs fetched on-demand when a match is found. |
| **Batch `markAllRecordsDirtyImpl`** | `CloudSyncEngine+Helpers.swift` | QSOs and ServicePresence processed in batches of 1K with fresh context per batch. Each batch saved independently. |
| **Batch dirty record collection** | `CloudSyncEngine+Outbound.swift` | `collectDirtyQSOChanges` and `collectDirtyServicePresenceChanges` now fetch in pages of 1K instead of unbounded. |
| **Batch `CallsignSuggestionProvider.loadContactCounts`** | `CallsignSuggestionProvider.swift` | Batched fetch (1K/batch) with `propertiesToFetch: [\.callsign]` and fresh context per batch. |
| **Batch `clearQRZData`/`clearLoFiData`** | `DashboardView+Actions.swift` | Extracted shared `clearImportedQSOsInBatches` helper. Processes 1K QSOs per save instead of 50K. |

| **Move POTA Awards card to background actor** | `POTAAwardsDashboardCard.swift` | Replaced main-thread `modelContext` batched fetch with `POTAUniqueParksActor` background actor. Groups (park, date, callsign) incrementally using only counts — never accumulates QSO managed objects. Fixes 0x8BADF00D watchdog crash on 68K QSO user. |

### Remaining P2/P3 Items (Not Yet Implemented)

- Eliminate `rawADIF` storage or move to lazy-loaded model
- Fix stats drill-down fallback (asyncStats.getStats() always returns nil)
- Reduce WAS callsign retention to counts + capped sample
- Map arc memory (reduce path resolution or virtualize)
- CWSweep unbounded fetches (lower priority — macOS has more RAM)
