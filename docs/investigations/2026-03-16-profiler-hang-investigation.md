# Profiler Hang Investigation Playbook

## Overview

Use the built-in startup profiler and hang detector to find main thread stalls, memory spikes, and performance regressions — then extrapolate to larger datasets using the scaling projection.

## Setup

1. **Enable profiler:** Settings → Developer → toggle "Startup Profiler"
2. **Relaunch the app** — profiling begins at `App.init()`
3. **Exercise the app:** Switch between all tabs (dashboard → logger → logs → activity → more), open/close sheets, trigger syncs
4. **Copy results:** Settings → Developer → Startup Profile → ellipsis menu → "Copy Hang Summary"
5. **Paste into a Claude conversation** for analysis

## Reading the Hang Summary

### Environment Section
- **QSO Count** — dataset size, used for scaling projections
- **Peak Memory / Memory Growth** — watch for growth approaching 1 GB (iOS kills around 1.5-2 GB depending on device)
- **Thermal / Low Power** — affects CPU scheduling; note if not Nominal

### Hang Details
Each hang shows:
- **Duration** — >200ms is noticeable, >500ms is a jank, >1s is a freeze
- **Memory at hang** — sudden spikes indicate large allocations on main thread
- **Correlated milestones:**
  - `After:` — last milestone before the hang started (likely trigger)
  - `During:` — milestones on background threads during the hang (shows what's running concurrently)
  - `Until:` — first milestone after the hang ended (shows what unblocked)

### Phase Durations
Automatically pairs `*.start` / `*.done` milestones. Sorted by duration (slowest first).
- **Record count + ms/rec** — appears when the milestone label includes a count like `stats.fetch.done(5545)`. Use ms/rec to compare across dataset sizes.
- **Memory delta** — `[+234 MB]` means that phase allocated 234 MB net. Large deltas indicate bulk data loading.

### Scaling Projection
Linear extrapolation for phases tagged as O(n) in QSO count. Shows projected cumulative time at 5K, 10K, 25K QSOs. Use this to predict whether a phase that's acceptable at your dataset size will become a problem at larger scales.

## Extrapolation Rules

### What scales linearly with QSO count (multiply by ratio)
| Phase | Why |
|-------|-----|
| `stats.fetch` | Fetches all QSOs in batches |
| `stats.sessions` | Fetches all LoggingSessions |
| `stats.basicCounts`, `stats.activations`, `stats.streaks`, `stats.countMetrics` | Single-pass over QSO snapshots |
| `gridTracker.load` | Queries all QSOs for grid data |
| `needs.compute` | Scans QSO history for DXCC/WAS gaps |
| `scp.userCallsigns` | Scans all QSOs for repeat callsigns |
| `presence` | ServicePresence count scales ~3x with QSOs |

### What does NOT scale with QSO count
| Phase | Why |
|-------|-----|
| `cache.refs` | Fixed reference data (POTA/SOTA/WWFF) |
| `friendSpots.load` | Network call, constant |
| `backup` | WAL checkpoint scales with recent writes only |
| `scp.diskLoad` | Fixed ~80K callsign file from disk |
| `settingsSync`, `clubsSync` | Network/config, not QSO-dependent |
| Tab switch rendering | View body evaluation (once data is computed) |

### Memory extrapolation
Memory scales roughly linearly with QSO count for data-loading phases. If `scp.userCallsigns` shows `[+50 MB]` for 1K QSOs, expect `[+250 MB]` for 5K QSOs. Watch for phases where memory delta × scale factor approaches 1 GB.

### How to extrapolate
```
your_qso_count = (from Environment section)
target_qso_count = 5545  (or whatever the target user has)
scale = target_qso_count / your_qso_count

For each linear-scaling phase:
  projected_duration = measured_duration × scale
  projected_memory = measured_memory_delta × scale

Total projected hang time ≈ sum of projected durations for phases that run on main thread
```

## Common Patterns

### Tab switch hangs
**Symptom:** Hangs correlated with `tab.switch.*` milestones.
**Cause:** `.task` modifiers re-fire on every tab switch (SwiftUI cancels on disappear, re-starts on appear). Views with unguarded `.task` re-run expensive work.
**Fix:** Add generation guards — only re-run when `dataGeneration` changes.
**Check:** Look for `dashboard.tabSwitch.skipped` (guard working) vs `dashboard.tabSwitch.recompute` (data changed, legitimate recompute).

### Memory spike during stats
**Symptom:** Large `[+NNN MB]` on `stats.fetch` or `scp.userCallsigns`.
**Cause:** SwiftData ModelContext retains full managed objects. Large batch sizes mean many objects alive simultaneously.
**Fix:** Reduce batch size, scope ModelContext in `do` blocks so objects are released between batches.

### Cascading hangs during startup
**Symptom:** Multiple small hangs (200-600ms) in sequence during first 2-5 seconds.
**Cause:** `waitUntilComplete()` blocks main actor continuation. Background work finishes but the continuation can't resume because other main actor work (stats rendering, SCP merge assignment) is queued.
**Fix:** Stagger result application with `Task.yield()` between stages. Ensure background computations don't need main actor for intermediate steps.

### Uninstrumented hangs (no milestones during hang window)
**Symptom:** A hang with `After:` and `Until:` milestones far apart, no `During:` milestones.
**Cause:** Code running on main thread without profiler instrumentation.
**Where to add milestones:** Dashboard card `.task` / `.onAppear` handlers, any `@MainActor` method called from view lifecycle, `@Observable` property mutations that trigger view re-evaluation.

## Adding New Instrumentation

Record milestones at the start and end of any potentially expensive operation:
```swift
StartupProfiler.shared.record("myFeature.start")
// ... expensive work ...
StartupProfiler.shared.record("myFeature.done")
```

For operations that process a known number of records, include the count:
```swift
StartupProfiler.shared.record("myFeature.done(\(count))")
```
This enables automatic ms/rec computation in the phase durations section.

To add a phase to the scaling projection, add its prefix to the `linearPhases` set in `StartupTrace+HangSummary.swift` → `appendScalingProjection`.

## Key Files

| File | Purpose |
|------|---------|
| `CarrierWave/Services/StartupProfiler.swift` | Profiler core: milestone recording, hang detection, persistence |
| `CarrierWave/Services/StartupTrace.swift` | Trace model, hang correlation, computed stats |
| `CarrierWave/Services/StartupTrace+HangSummary.swift` | Hang summary text generation, phase duration analysis, scaling projection |
| `CarrierWave/Services/MainThreadHangDetector.swift` | Background thread that pings main run loop, detects >200ms stalls |
| `CarrierWave/Views/Settings/StartupProfileView.swift` | Profile viewer UI, copy/share/import |

## Historical Findings (2026-03-16)

### Root cause of 1.8s hangs on 5545-QSO dataset
Every dashboard sub-view's `.task` modifier re-fired on tab switch, causing:
- `GridTrackerCard` — recomputed grid summary from all QSOs (0.234s per switch, 213 MB spike)
- `NeedsEngine.recompute()` — re-scanned QSO history (0.601s)
- `FriendsOnAirCard` — hit POTA API 7 times (accumulated `.task` re-fires)
- `ActivityLogCard` — Keychain read on every `.onAppear`

**Fix:** Added generation guards to skip redundant work when data hasn't changed. Result: 21 hangs → 2 hangs, 9.3s → 0.4s cumulative.

### SCP memory spike
`fetchRepeatCallsigns` loaded 1000 QSO objects per batch into SwiftData ModelContext (+234 MB for 1082 QSOs). `SCPDatabase.merging` created 4 copies of 80K callsigns simultaneously.

**Fix:** Reduced batch size to 200 with `autoreleasepool` wrapper to force SwiftData internal object release between batches. Rewrote `merging` to use in-place Set insertion + merge-sort, avoiding intermediate array copies. Added internal init to skip re-sort/re-dedup. Result: +184 MB → -10 MB net memory delta.

### Backup memory overlap
Phase duration showed backup as +329 MB, but this was a measurement artifact — backup ran concurrently with SCP loading, stats, and service configuration during startup. The memory delta between `backup.start` and `backup.complete` included all concurrent work.

**Fix:** Deferred backup by 2 seconds so it runs after startup memory settles. Result: backup now shows +0 MB delta (403 MB flat throughout).

### FriendsOnAirCard duplicate network calls
`.onReceive(.didSyncQSOs)` had no guard — sync posts multiple notifications per batch, causing 5+ redundant POTA API calls per launch.

**Fix:** Added 5-second debounce to the sync notification handler. Combined with the existing `hasLoadedSpots` guard on `.task(id:)`, loads reduced from 5 to 2.

### NeedsEngine breakdown
Added inner instrumentation (`needs.ctyLoad`, `needs.accumulate`) revealing the 0.411s `needs.compute` was:
- CTY database load: 0.207s (51%) — disk read + parse of cty.dat, constant cost, runs on background thread
- QSO accumulation: 0.102s (25%) — actual per-QSO processing, scales linearly
- Finalization: 0.093s (24%)

**Fix:** Fixed duplicate `ModeEquivalence.family()` call (computed twice per QSO). Added `autoreleasepool` to batch loop with reduced batch size (500). CTY load is background-only and not a hang contributor.

### Final results (1082 QSOs, iPhone 18,1)

| Metric | Original (5545 QSOs, iPhone 17,2) | Final (1082 QSOs, iPhone 18,1) | Projected at 5545 |
|--------|-----|-----|------|
| Hangs | 21 (9.3s) | 1 (0.2s) | ~1-2 (0.2-0.4s) |
| Peak memory | 893 MB | 657 MB | ~700-800 MB |
| SCP memory delta | +234 MB | -10 MB | ~-50 MB |
| Backup overlap | +329 MB concurrent | +0 MB deferred | +0 MB |
| Tab switch recomputes | Every switch | Skipped (generation guard) | Skipped |
| Friend spot loads | 7 per launch | 2 per launch | 2 per launch |
