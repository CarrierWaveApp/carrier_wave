# Investigation: LoFi QSO Count Gap (13282 vs 13218)

**Date:** 2026-02-11
**Status:** Resolved
**Outcome:** 65 QSOs lost to dedup-key grouping. ~half were legit dupes (same park, different UUIDs), ~half were two-fer activations where park references were being dropped. Fixed merge logic to combine park references instead of "first wins".

## Problem Statement

Dave (W4DHW) confirmed that the LoFi server reports the same QSO counts as the CLI tool downloads. However, after sync the app shows 13218 QSOs while the CLI pipeline shows 13282 valid QSOs after field checking. Where do 64 QSOs vanish?

Additionally, the raw fetch count was exactly double the deduped count (26566 vs 13283), suggesting unnecessary double-fetching.

## Hypotheses

### Hypothesis 1: Deleted QSO double-fetch causes 2x raw count
- **Evidence for:** Raw count (26566) was exactly 2x deduped count (13283). The `fetchQsosForOperation` method looped over `deleted in [false, true]`.
- **Evidence against:** None
- **Tested:** Yes
- **Result:** Confirmed. The LoFi QSO endpoint **ignores** the `deleted` param (unlike the operations endpoint). Every QSO was fetched twice. The `QSODownloadAccumulator` UUID dedup then collapsed them back, but we wasted bandwidth.

### Hypothesis 2: FetchedQSO.fromLoFi field validation drops QSOs
- **Evidence for:** `fromLoFi` returns nil if `theirCall`, `band`, `mode`, or `timestamp` is missing. CLI Step 3 showed 1 QSO dropped.
- **Tested:** Yes (via CLI Step 3)
- **Result:** Only 1 QSO dropped here. Not the source of the 64 gap.

### Hypothesis 3: Deduplication key grouping collapses QSOs across operations
- **Evidence for:** `QSOProcessingActor.processDownloadedQSOs` groups by `deduplicationKey` = `"CALLSIGN|BAND|MODE|roundedTimestamp"` where timestamp is rounded to 2-minute buckets. If the same contact appears in multiple LoFi operations (e.g., re-logged, copied between sessions), they share a dedup key and get merged into one QSO.
- **Evidence against:** None
- **Tested:** Added Step 4 to CLI pipeline breakdown to count unique dedup keys
- **Result:** This accounts for the 64 gap. 13282 QSOs with valid fields collapse to ~13218 unique dedup keys.

## Investigation Log

### Step 1: Trace the full pipeline
1. `LoFiClient.fetchAllQsosSinceLastSync()` downloads raw QSOs, deduplicates by UUID
2. `SyncService+Download.convertLoFiQSOsWithYielding()` calls `FetchedQSO.fromLoFi()` (field filter)
3. `SyncService.processDownloadedQSOsAsync()` → `QSOProcessingActor.processDownloadedQSOs()`
4. `groupByDeduplicationKey()` groups FetchedQSOs by `callsign|band|mode|2min-bucket`
5. For each group: merge into existing DB row or create new QSO

Step 4 is the "hidden" reduction the CLI didn't show.

### Step 2: Understand dedup key computation
```swift
// FetchedQSO.deduplicationKey
let rounded = Int(timestamp.timeIntervalSince1970 / 120) * 120  // 2-minute buckets
return "\(callsign.uppercased())|\(band.uppercased())|\(mode.uppercased())|\(rounded)"
```

This intentionally ignores `myCallsign` and `operation` — it treats the same contacted station on the same band/mode/time as one QSO regardless of which operation or logging session it was in.

### Step 3: Fix double-fetch
Removed the `for deleted in [false, true]` loop in `fetchQsosForOperation` in `LoFiClient+Sync.swift`. Added comment explaining that the QSO endpoint always returns both active and deleted QSOs.

### Step 4: Add pipeline Step 4 to CLI
Added dedup-key simulation to `printPipelineBreakdown` in `LoFiCLI.swift` so the CLI shows where these 64 QSOs go. Now shows all 4 steps matching the app pipeline.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `LoFiClient+Sync.swift` | Sync orchestration | Had `for deleted in [false, true]` causing double-fetch |
| `SyncService+Download.swift` | App download flow | `convertLoFiQSOsWithYielding` applies `FetchedQSO.fromLoFi` filter |
| `FetchedQSO.swift` | Field validation + dedup key | `fromLoFi` returns nil on missing fields; `deduplicationKey` uses 2-min buckets |
| `QSOProcessingActor.swift` | Background processing | `groupByDeduplicationKey` is where the 64 QSOs collapse |
| `SyncService+Process.swift` | Process orchestration | Delegates to `QSOProcessingActor` for background work |
| `LoFiModels+QSO.swift` | LoFi computed properties | `timestamp` computed from `startAtMillis / 1000` |
| `~/projects/api-lofi/app/controllers/api/v1/qsos_controller.rb` | Server-side | Confirmed QSO endpoint has no `deleted` filtering |

## Root Cause

Three issues:

1. **Double-fetch (fixed):** `fetchQsosForOperation` fetched QSOs twice (once for `deleted=false`, once for `deleted=true`) but the server ignores the `deleted` param on QSOs. This doubled bandwidth for no reason.

2. **Dedup key grouping (expected, now visible):** The app's `deduplicationKey` groups QSOs with the same callsign+band+mode within a 2-minute window. Dave has 65 such collisions. The dedup itself is correct — same RF contact = same QSO.

3. **Two-fer park references lost (BUG, fixed):** During merge, `parkReference` used "first wins" logic (`nonEmpty ?? other`). For two-fer activations where the same contact appears in two operations (one per park, e.g., US-3984 and US-9944), the second park reference was silently dropped. Dave's data showed ~15 such two-fer collisions where different parks were being lost.

## Resolution

1. Removed deleted QSO double-fetch from `LoFiClient+Sync.swift`
2. Added Step 4 to CLI pipeline breakdown showing dedup-key grouping with per-QSO detail
3. **Fixed park reference merge** in all four merge paths:
   - `QSOProcessingActor.mergeFetchedGroup` — combine parks instead of first-wins
   - `QSOProcessingActor.mergeIntoExisting` — combine parks instead of first-wins
   - `SyncService+Process.mergeFetchedGroup` — combine parks instead of first-wins (legacy)
   - `SyncService+Process.mergeIntoExisting` — combine parks instead of first-wins (legacy)
4. Added `FetchedQSO.combineParkReferences` helper that splits, deduplicates, sorts, and rejoins

## Lessons Learned

- The LoFi QSO endpoint does NOT respect the `deleted` parameter — only the operations endpoint does. Always check server behavior, not just API docs.
- The dedup key is intentionally coarse (2-minute buckets, ignoring myCallsign/operation). This is by design to merge the same contact from multiple sources/sessions.
- CLI diagnostic pipelines should mirror the FULL app pipeline, including post-download processing steps, to avoid confusing count discrepancies.
- Park references must be COMBINED during merge, not "first wins". Two-fer activations create separate LoFi operations per park, so the same QSO appears in multiple operations with different park refs.
