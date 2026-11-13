# Startup Profile Analysis: iPhone 17,2 (iOS 26.3.1)

**Date:** 2026-03-15
**Device:** iPhone17,2 (iPhone 16 Pro Max)
**OS:** Version 26.3.1 (Build 23D8133)
**Total startup:** 2.12s (profiler.started to profiler.finished)

## Timeline

```
0.000s  profiler.started
0.000s  init.tabMigration
0.437s  init.keychainMigration          ← 437ms on main thread
0.460s  init.schemaBuilt                   (23ms)
0.460s  init.restoreCheck                  (<1ms)
0.480s  init.modelContainer                (20ms)
0.617s  repair.potaSyncState               (<1ms)
0.617s  repair.bandCase                    (<1ms)
0.617s  settingsSync.start
0.637s  settingsSync.done                  (20ms)
0.638s  remoteNotifications.registered
0.638s  backup.start
0.638s  backup.qsoCount           [bg]
0.642s  yield.firstFrame          ← first frame at 642ms
0.646s  notesSources.mirrored
0.648s  watchConnectivity.activated
0.655s  yield.preServices
0.655s  solarPolling.configured
0.655s  contestPolling.configured
0.657s  cloudSync.configured
0.683s  backup.qsoCountDone       [bg]    (45ms)
0.694s  clubsSync.configured
0.756s  yield.preSCP
0.757s  backup.walCheckpoint      [bg]
0.757s  qrqCrew.seeded
0.757s  scp.diskLoad
0.760s  backup.createSnapshot     [bg]
0.764s  backup.manifest           [bg]
0.767s  backup.pruneLocal         [bg]
0.769s  backup.syncICloud         [bg]
0.769s  backup.complete           [bg]    (131ms total)
0.779s  scp.diskLoaded                     (22ms)
0.779s  scp.userCallsigns.fetch
0.779s  scp.userCallsigns.query   [bg]
1.639s  cache.pota                [task2]  (861ms from scp.diskLoad)
1.937s  scp.userCallsigns.queryDone [bg]   (1,158ms query)
2.122s  scp.userCallsigns.merged           (185ms merge)
2.122s  profiler.finished
```

## Bottleneck Analysis

### 1. Keychain Migration — 437ms (main thread, blocking)

**File:** `CarrierWave/Utilities/KeychainHelper+Migration.swift`

This is a one-time migration that copies 21 credential keys to the shared iCloud Keychain group. It's guarded by a UserDefaults flag (`sharedGroupMigrationComplete`), but on this user's device it ran fully, meaning:
- Either this is their first launch after the migration was added
- Or the flag was somehow cleared

**Impact:** Blocks `init()` on main thread. Nothing else can start until this completes.

**Observations:**
- 437ms for 21 keychain reads + conditional writes is surprisingly slow
- Each key does a `SecItemDelete` + `SecItemAdd` to the iCloud-synced group
- iCloud Keychain operations are known to be slow due to hardware security module involvement
- On subsequent launches this should be <1ms (flag check only)

**Recommendation:** This is acceptable for a one-time migration. No action needed unless users report repeated slow launches (which would indicate the flag is being reset).

### 2. SCP User Callsigns Query — 1,158ms (background thread)

**File:** `CarrierWave/Services/SCPService.swift:95-135`

Fetches all non-hidden, non-metadata QSOs in batches of 1,000 to find callsigns worked 2+ times. The query uses `propertiesToFetch = [\.callsign]` for efficiency, but still iterates the entire QSO table.

**Why it's slow:**
- Iterates ALL QSOs regardless of count — no early termination
- Each batch creates a new `ModelContext` (line 110) — this is correct for memory but adds overhead
- The predicate filters on `isHidden` and three mode strings — SwiftData may not have optimal indexes for this
- On a device with thousands of QSOs, this is O(n) with constant factor overhead per batch

**Impact:** Runs on background thread but `await`ed on main — profiler can't finish until this completes. The 185ms merge back to main at the end is also notable.

**Potential optimizations:**
1. **Use a SQL-level GROUP BY/HAVING** if SwiftData supported it (it doesn't) — consider a raw SQLite query
2. **Cache the result** across launches and only scan QSOs added since last check (store last-checked timestamp or QSO count)
3. **Increase batch size** — 1,000 is conservative; 5,000-10,000 would reduce round-trips
4. **Defer to post-startup** — this augments autocomplete, not critical for first interaction

### 3. POTA Cache — 861ms (separate task, non-blocking)

**File:** `CarrierWave/Services/POTAParksCache.swift`

Loads and parses a multi-MB CSV of all POTA parks. Runs in a separate `.task{}` so it doesn't block the critical path or first frame.

**Impact:** Low — this runs concurrently in task2 and doesn't block the profiler's critical path. The 861ms is for disk I/O + CSV parsing + name index building.

**No action needed** — already correctly off the critical path and sequenced with SOTA/WWFF to limit peak memory.

## Profiler Blind Spot: The 10-Second Tab Switch

The profiler finishes at 2.12s, but a user reported it took **10 full seconds** to
switch back to the Dashboard tab after initially navigating away. The profiler captures
zero of this — it only measures CarrierWaveApp's init/task chain.

### Root cause: thundering herd on Dashboard appear

When `hasLoadedDashboard` becomes true (DashboardView.swift:160-169), four stat
computations fire **simultaneously**:

1. `asyncStats.compute()` — full QSO table scan in 2,000-batch fetches
2. `equipmentStats.compute()` — LoggingSession scan
3. `presenceCounts.compute()` — ServicePresence scan in 500-batch fetches
4. `bragSheetStats.compute()` — ANOTHER full QSO table scan (20-30 MB on large DBs)

Each dispatches to its own background actor with its own `ModelContext(container)`.
This is correct for thread safety, but creates massive **SQLite contention** — 4+
concurrent readers all paging through the same database simultaneously.

### @Observable update storm

`AsyncQSOStatistics` sends progress updates every 0.1s via `Task { @MainActor }`,
mutating `@Observable` properties (`progress`, `progressPhase`). Each mutation triggers
SwiftUI to re-evaluate any view reading those properties.

The Dashboard body is **~15 cards across 5 collapsible sections**
(DashboardView+Layout.swift). Many cards read from `asyncStats`, `equipmentStats`,
`presenceCounts`, and `bragSheetStats`. With 4 stat types computing and updating
simultaneously, the Dashboard body gets re-evaluated dozens of times during startup.

### Concurrent load from other systems

While stats compute, these also run concurrently:
- **Repair chain** (DashboardView:170-195): 14 sequential `await` calls on MainActor
- **Cache loading** (CarrierWaveApp task2): POTA + SOTA + WWFF CSV parsing
- **CloudSync init**: CKSyncEngine (described as "heavyweight")
- **Backup service**: WAL checkpoint + snapshot
- **SCP callsigns**: full QSO table scan (now fire-and-forget)

All competing for SQLite access, CPU, and memory.

### Why the tab switch freezes

The user taps away from Dashboard immediately (tab bar is responsive at first frame).
Background work continues. When they tap back:

1. SwiftUI displays the Dashboard view, which reads `@Observable` stat objects
2. Stats are mid-computation → progress callbacks are firing every 0.1s
3. Each `@Observable` mutation triggers a full body re-evaluation (~15 cards)
4. SQLite contention from concurrent background work slows everything
5. The main thread is saturated processing change notifications + view layouts
6. Tab switch animation is queued behind all this main-thread work → **10s delay**

### Secondary issues

**Activity tab @Query decorators** (ActivityView.swift:22-36): 4 unbounded `@Query`
properties evaluate at LazyTabContent construction, adding more SQLite pressure.

**Logs tab unbounded fetchCount** (LogsListView.swift): O(n) count on full QSO table.

## Recommended Fixes

### Priority 1: Stagger stat computations (high impact)

Instead of firing all 4 simultaneously (DashboardView.swift:160-169):
```swift
// Current: all 4 fire at once
asyncStats.compute(from: modelContext)
equipmentStats.compute(from: modelContext.container)
presenceCounts.compute(from: modelContext)
bragSheetStats.compute(from: modelContext.container)
```

Stagger them sequentially — complete one before starting the next. This eliminates
SQLite contention between stat computations and reduces peak memory. Prioritize
`asyncStats` (above-the-fold streaks/counts) and `presenceCounts` (sync status).

### Priority 2: Reduce progress update frequency

Change `AsyncQSOStatistics.progressUpdateInterval` from 0.1s to 0.5s+ to reduce
@Observable mutation frequency and resulting view re-evaluations.

### Priority 3: Defer brag sheet computation

`bragSheetStats` does a SECOND full QSO table scan. It's only visible if the user
scrolls to the Brag Sheet card. Defer it until the card is actually visible, or
at minimum run it after `asyncStats` completes (sharing the same snapshot data).

### Priority 4: Add profiler milestones to Dashboard

Add `StartupProfiler.shared.record()` calls to DashboardView's `.task` chain to
capture stats computation timing in the profile trace. This will make the gap visible
in future profiles.

## Changes Made

### SCP user callsigns deferred (CarrierWaveApp.swift:191)

Changed from `await SCPService.shared.loadUserCallsigns(container:)` to fire-and-forget
`Task { ... }`. This removes 1.34s (query + merge) from the critical startup path.
SCP callsign augmentation only enhances autocomplete — not needed before the user
starts typing.

## Summary

| Bottleneck | Duration | Thread | Blocking? | Action |
|-----------|----------|--------|-----------|--------|
| Keychain migration | 437ms | main | Yes (init) | None — one-time only |
| SCP callsigns query | 1,158ms | background | ~~Awaited~~ | **Fixed** — fire-and-forget |
| POTA cache | 861ms | task2 | No | None — already off critical path |
| Stats thundering herd | ~10s (reported) | bg→main | **Yes** | Stagger computations |
| Progress updates | 0.1s interval | main | Yes (re-renders) | Reduce frequency |
| Brag sheet scan | unmeasured | background | Indirect | Defer until visible |

**First frame:** 642ms — acceptable.
**Time to interactive (Dashboard):** ~10s (user-reported) — unacceptable.

The profiler shows 2.12s, but the actual time-to-interactive is dominated by
view-level work that fires after the profiler finishes.

## Comparison Notes

- QSO count is the primary scaling factor — stats scan the entire table (twice for brag sheet)
- Keychain migration is one-time — subsequent launches won't show this
- POTA cache time depends on whether it's disk-cached or needs download
- More QSOs = longer stat computation = more progress updates = more re-renders
