# Startup Profile Analysis: iPhone 17 Pro (Profiling Data #2)

**Date:** 2026-03-15
**Device:** iPhone 17 Pro (iPhone18,1)
**Context:** Second profiling run with dashboard milestones enabled (per Priority 4 from previous investigation). This captures the full picture including post-startup dashboard stat computation times.

## Full Timeline

```
0.000s  app launch
0.324s  backup.manifest           [bg]
0.324s  scp.diskLoad              [main]
0.326s  backup.pruneLocal         [bg]
0.329s  backup.syncICloud         [bg]
0.329s  backup.complete           [bg]
0.352s  scp.diskLoaded            [main]
0.352s  startup.complete          [main]     ← core startup done
0.358s  dashboard.qrzConfig       [main]
0.366s  dashboard.serviceStatus   [main]
0.366s  dashboard.statsStart      [main]     ← stats computation begins
0.575s  dashboard.repairs.start   [main]     ← repair chain begins (after 500ms sleep)
0.575s  scp.userCallsigns.query   [bg]
1.567s  dashboard.asyncStatsComplete [main]  ← computation done (+0.99s)
1.795s  scp.userCallsigns.queryDone  [bg]   (+0.23s)
7.527s  dashboard.asyncStats.done [main]     ← waitUntilComplete resumes (+5.73s GAP)
7.527s  dashboard.presenceCounts.start [main]
7.946s  cache.pota                [task2]    (+0.42s)
7.957s  scp.userCallsigns.merged  [main]
7.961s  dashboard.repairs.done    [main]     ← repair chain ends (7.39s total)
8.000s  tab.switch.activity       [main]
8.016s  lazy.loaded.activity      [main]
8.806s  clubsSync.fetched         [main]    (+0.79s)
10.195s cache.sota                [task2]   (+1.39s)
11.307s dashboard.presenceCountsComplete [main] (+1.11s)
11.327s dashboard.presenceCounts.done    [main]
11.327s dashboard.equipmentStats.start   [main]
11.354s dashboard.equipmentStats.done    [main]  (0.03s — fast)
11.354s dashboard.bragSheet.start        [main]
11.956s cache.wwff                [task2]   (+0.60s)
11.959s cache.notes               [task2]
12.067s dashboard.bragSheetComplete      [main]  (+0.71s)
12.080s dashboard.bragSheet.done         [main]
12.080s dashboard.statsComplete          [main]  ← all dashboard stats done
14.279s tab.switch.more           [main]    (+2.20s)
```

**Total time to interactive dashboard:** ~12s from launch
**Core startup:** 0.352s (fast)

## Bottlenecks >1 Second

### 1. Main Actor Contention Gap — 5.73s (CRITICAL)

**Observed:** `asyncStatsComplete` fires at 1.567s, but `asyncStats.done` (the `waitUntilComplete()` resume) doesn't fire until 7.527s.

**The stats computation itself takes only ~1s.** The 5.73s gap is caused by main actor contention — the `waitUntilComplete()` continuation is queued on `@MainActor` but can't execute because:

1. **Repair chain holds the main actor (7.39s total):** 14 sequential repair functions run from `DashboardView+Repairs.swift` in a concurrent `.task(id: hasLoadedDashboard)`. The repair chain starts at 0.575s and finishes at 7.961s. Between repair `await` calls, the main actor briefly yields, but repairs re-acquire it before the `waitUntilComplete()` continuation can run.

2. **@Observable update storm:** `applyResults()` sets 30+ `@Observable` properties on `AsyncQSOStatistics` at 1.567s. Each mutation triggers SwiftUI observation tracking and dashboard view re-evaluation (~15 cards across 5 sections). This queues significant layout work on the main actor.

3. **Combined effect:** The repair chain monopolizes main actor time between its suspension points, while SwiftUI layout work from the @Observable storm fills any remaining gaps.

**Evidence:** `repairs.done` (7.961s) aligns closely with `asyncStats.done` (7.527s) — the repair chain finishing is what unblocks the stats continuation.

**Key repair issues found:**
- `backfillWPMIfNeeded`: **UNBOUNDED** — fetches ALL LoggingSession + ALL ActivationMetadata with no fetchLimit
- `backfillConditionsIfNeeded`: **UNBOUNDED** — fetches ALL ActivationMetadata records
- `repairPOTAMidnightSplitIfNeeded`: **@MainActor** — DB work on main thread (violates performance rules)
- `backfillSessionClubMembersIfNeeded`: Uses main context directly, not a background actor

### 2. SOTA Cache — 1.39s

**File:** `CarrierWave/Services/SOTASummitsCache+Parsing.swift`

Parses the SOTA summitslist.csv (~130k summits) line by line, building a `[String: SOTASummit]` dictionary plus a sorted name index for prefix search.

**Why it's slow:**
- `parseCSV()` iterates every line of a multi-MB CSV, calling `CSVLineParser.parseCSVLine()` per line
- Each line creates a `SOTASummit` struct with ~15 fields including `Int()` and `Double()` conversions
- `buildNameIndex()` then iterates all summits again, splits names into words, builds a `[String: [String]]` index, sorts it

**Impact:** Runs in a separate `.task{}` (not on critical path), but sequential after POTA cache (0.42s). Contends for CPU with dashboard stats and repairs running concurrently.

**Potential optimizations:**
1. Binary/MessagePack cache — parse CSV once, persist structured data for subsequent launches
2. Lazy index building — defer `buildNameIndex()` until first search
3. Concurrent parsing — split CSV into chunks, parse in parallel

### 3. Presence Counts — 1.11s

**File:** `CarrierWave/Views/Dashboard/AsyncServicePresenceCounts.swift`

`PresenceComputationActor.computeCounts()` scans the entire `ServicePresence` table in 500-record batches.

**Why it's slow:**
- No predicate filtering — fetches ALL ServicePresence records regardless of type
- Relationship traversal: `presence.qso` for every record to check `isHidden` and get `qso.id`
- Builds `Set<UUID>` per service type (6 services × 2 directions = 12 sets)
- 500-record batch size is conservative — each batch creates overhead

**Potential optimizations:**
1. **Increase batch size** to 2,000-5,000 (background thread, no UI concern)
2. **Filter by service type** — separate queries per service with predicate pushdown
3. **Cache counts** — store counts and only rescan QSOs added since last computation
4. **Skip relationship traversal** — if ServicePresence stored `qsoId` as a direct property, avoid faulting the QSO relationship

### 4. Tab Switch to More — 2.20s

**Observed:** `tab.switch.more` fires at 14.279s with +2.20s delta from `dashboard.statsComplete`.

This is the time for the "More" tab to appear after tapping it. Likely caused by:
- View construction overhead (More tab likely contains settings, debug tools, etc.)
- Residual main actor saturation from the preceding 12s of work
- Possible `@Query` or `FetchDescriptor` evaluation on tab construction

**Needs further instrumentation** to determine root cause.

## Cascading Impact Analysis

The staggered stats design (Priority 1 from previous investigation) is correctly implemented, but its benefit is negated by the repair chain running concurrently:

```
Stats task:     [asyncStats 1s]----BLOCKED 5.7s----[presence 1.1s][equip 0.03s][brag 0.7s]
Repair task:    [sleep 0.5s][----14 sequential repairs for 7.4s total----]
Cache task:     [pota 0.4s][sota 1.4s][wwff 0.6s][notes]
```

The repair chain doesn't yield the main actor frequently enough, so even though asyncStats finishes in 1s, the staggered pipeline can't advance for 5.7s. This serializes everything after it.

**If the repair chain didn't block:** `presenceCounts` would start at ~1.6s instead of 7.5s, saving ~6s off the total dashboard load time. The full pipeline would complete in ~4s instead of ~12s.

## Recommendations

### Priority 1: Move repair chain after stats pipeline (HIGH IMPACT)

The repair chain (`DashboardView.swift:194-222`) runs concurrently with stats but blocks main actor for 7.4s. Move it to run AFTER `dashboard.statsComplete`:

```swift
// Option A: Sequential — repairs run after stats
.task(id: hasLoadedDashboard) {
    // ... stats pipeline (current lines 161-192) ...
    profiler.record("dashboard.statsComplete")

    // Now run repairs (previously in separate .task)
    try? await Task.sleep(for: .milliseconds(200))
    await runRepairChain()
}
```

This would reduce time-to-interactive from ~12s to ~4s.

### Priority 2: Fix unbounded repair fetches

- `backfillWPMIfNeeded`: Add `fetchLimit` to LoggingSession and ActivationMetadata descriptors
- `backfillConditionsIfNeeded`: Add `fetchLimit` to ActivationMetadata descriptor
- `repairPOTAMidnightSplitIfNeeded`: Move off `@MainActor` to background actor
- `backfillSessionClubMembersIfNeeded`: Use background `ModelContext(container)` instead of main context

### Priority 3: Increase PresenceComputationActor batch size

Change `fetchBatchSize` from 500 to 2,000. This is a background actor — larger batches reduce round-trip overhead without UI impact.

### Priority 4: Binary cache for SOTA summits

Parse CSV once, serialize to a binary format (Codable + Data, or MessagePack) for subsequent launches. Would reduce 1.39s to <100ms on cache hit.

### Priority 5: Batch @Observable updates in applyResults

`applyResults()` sets 30+ @Observable properties sequentially, each triggering SwiftUI change tracking. Consolidate into fewer update points or use `withObservationTracking` to batch.

## Comparison with Previous Profile

| Metric | iPhone 16 Pro Max | iPhone 17 Pro | Notes |
|--------|------------------|---------------|-------|
| Core startup | 2.12s | 0.352s | Keychain migration was one-time |
| asyncStats computation | unmeasured | ~1.0s | Now instrumented |
| Main actor gap | ~10s (reported) | 5.73s (measured) | Repair chain is root cause |
| Presence counts | unmeasured | 1.11s | Now instrumented |
| SOTA cache | unmeasured | 1.39s | Now instrumented |
| Total dashboard ready | ~10s (reported) | 12.08s (measured) | Full picture now visible |

## Summary

| Bottleneck | Duration | Root Cause | Fix Priority |
|-----------|----------|------------|--------------|
| Main actor contention | 5.73s | Repair chain blocks stats pipeline | P1 — reorder |
| SOTA cache parse | 1.39s | CSV parsing ~130k lines | P4 — binary cache |
| Presence counts | 1.11s | Full table scan, small batches | P3 — increase batch size |
| Tab switch (More) | 2.20s | Unknown — needs instrumentation | Investigate |
| Unbounded repairs | contributes to P1 | No fetchLimit on 2 repairs | P2 — add limits |

---

## Profiling Run #3 (2026-03-15, post P1-P3 fixes)

Third profiling run after implementing P1 (repairs after stats), P3 (batch size 2000).

### New Timeline

```
0.399s  dashboard.statsStart           ← stats pipeline begins
0.399s  dashboard.asyncStats.start
0.628s  dashboard.statsStart           ← DUPLICATE (SwiftUI double-eval)
0.628s  dashboard.asyncStats.start     ← DUPLICATE
1.450s  dashboard.asyncStatsComplete   (+0.822s computation)
1.553s  dashboard.asyncStats.done      (+0.102s)
1.553s  dashboard.presenceCounts.start
1.757s  scp.userCallsigns.queryDone    (+0.204s)
7.354s  cache.pota                     (+5.597s — network download, cache expired)
7.851s  scp.userCallsigns.merged
8.250s  tab.switch.logger
9.582s  tab.switch.activity            (+0.925s)
9.784s  cache.sota                     (+0.202s — fast, CSV hit)
10.784s tab.switch.dashboard           (+1.000s)
11.229s dashboard.statsStart           ← 3RD run (.task(id:) re-fires on tab reappear)
11.516s dashboard.presenceCountsComplete (+0.288s)
11.688s dashboard.bragSheet.start
13.199s cache.wwff                     (+1.510s — CSV parse, no binary cache)
13.604s dashboard.bragSheetComplete    (+0.400s)
13.623s dashboard.bragSheet.done       (fires 3x — 3 pipeline instances)
13.623s dashboard.statsComplete        (fires 3x)
13.837s dashboard.repairs.start
16.111s tab.switch.more                (+2.274s)
```

### Key Findings

1. **Stats pipeline fires 3x** — `.task(id: hasLoadedDashboard)` re-fires on SwiftUI double-evaluation (0.399s + 0.628s) and on tab reappear (11.229s). Each instance runs the full pipeline independently.

2. **cache.pota 5.6s** — Network download (14-day cache expired). Previous profile showed 0.42s on disk cache hit. Not a regression — just cache expiry.

3. **P1 fix confirmed working** — Repairs start at 13.837s, AFTER statsComplete. No main actor contention gap (asyncStatsComplete → asyncStats.done = 0.1s vs 5.7s before).

4. **P3 fix confirmed** — Batch size 2000, presenceCounts completes in 0.288s (vs 1.11s before with 500 batch size).

5. **cache.wwff 1.5s** — CSV parsing still slow on disk cache hit.

### Fixes Applied

#### Fix 1: Prevent duplicate stats pipeline execution
Added `hasRunStatsPipeline` flag to `DashboardView`. The `.task(id:)` now guards against re-execution after the first successful run. Tab-switch recomputes are handled by `.onChange(of: selectedTab)` with generation guards.

**Expected impact:** Eliminates 2 redundant pipeline executions, saving ~2-3s of background computation and avoiding @Observable update storms.

#### Fix 2: Move backfillSessionClubMembersIfNeeded to background context
Refactored to use `Task.detached` with a background `ModelContext(container)` instead of the main context. Prevents main thread blocking during QSO fetches for club member lookups.

#### Fix 3: Binary cache for POTA/WWFF/SOTA
Added JSON-encoded binary cache alongside CSV disk cache. After first CSV parse, the parsed dictionary is serialized to `.bin` file. Subsequent launches load the binary cache directly, skipping CSV line-by-line parsing.

- Made `POTAPark`, `WWFFReference`, `SOTASummit` conform to `Codable`
- Added `saveBinaryCache`/`loadBinaryCache`/`invalidateBinaryCache` to `ReferenceCacheDiskIO`
- Binary cache auto-invalidates when CSV is newer (fresh download)

**Expected impact:** SOTA 1.39s → <200ms, WWFF 1.5s → <200ms, POTA 0.42s → <100ms on binary cache hits.

#### Fix 4: Non-blocking network downloads for cache loading
Refactored `ensureLoaded()` in all three caches (POTA, WWFF, SOTA) so that network downloads never block the caller. When no disk cache exists (first launch or cache cleared), the method marks the cache as loaded (empty), starts a fire-and-forget background download, and returns immediately. Lookups return nil until the download completes and populates the cache.

Previously, `ensureLoaded()` would `await` the full network download (5.6s for POTA in this profile), blocking the sequential cache loading pipeline in `CarrierWaveApp.swift` — SOTA and WWFF couldn't start until POTA finished downloading.

**Expected impact:** Eliminates 5.6s+ blocking on cache expiry. All three caches load from disk instantly or return empty and download concurrently in background.
