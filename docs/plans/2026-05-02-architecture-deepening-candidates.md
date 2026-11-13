# Architecture Deepening Candidates — iOS

Date: 2026-05-02
Source: `/improve-codebase-architecture` exploration of `swift/ios/`.

Vocabulary used throughout: **module** (interface + implementation), **interface** (everything a caller must know), **depth** (leverage at the interface), **seam** (where an interface lives), **adapter** (concrete satisfier of an interface at a seam), **locality** (change/bugs/knowledge concentrated in one place).

Apply the **deletion test** to anything suspected shallow: would deleting it concentrate complexity (earned its keep) or just move it (was a pass-through)?

---

## 1. Repair Pipeline — collapse a fleet of shallow modules

**Files involved:**
- `swift/ios/CarrierWave/Services/DataRepairService.swift` (orchestrator + UserDefaults gates)
- `swift/ios/CarrierWave/Services/CommentParkRefRepairService.swift`
- `swift/ios/CarrierWave/Services/HuntingParkRefRepairService.swift`
- `swift/ios/CarrierWave/Services/KIndexRepairService.swift`
- `swift/ios/CarrierWave/Services/DuplicateSpotNoteRepairService.swift`
- `swift/ios/CarrierWave/Services/PhoneSSBDuplicateRepairService.swift`
- `swift/ios/CarrierWave/Services/ServicePresenceDeduplicationRepairService.swift`
- `swift/ios/CarrierWave/Services/TwoferDuplicateRepairService.swift`
- `swift/ios/CarrierWave/Services/POTAPresenceRepairService.swift`
- `swift/ios/CarrierWave/Services/POTASplitRepairService.swift`
- `swift/ios/CarrierWave/Services/ActivityLogQSORepairService.swift`
- `swift/ios/CarrierWave/Services/WPMBackfillService.swift`
- `swift/ios/CarrierWave/Services/ConditionsBackfillService.swift`

**Friction:** ~12 services with near-identical shape (predicate → batched fetch → mutation → save → idempotency gate via UserDefaults), each exposing a different one-off interface. The shared depth — batched mutation with checkpoints on a fresh `ModelContext` — is reimplemented every time.

**Deletion test:** Removing the family concentrates complexity into one `RepairPipeline` seam; ~12 adapters describe *what to repair*, not *how to batch*.

**Tests improve:** Batching invariants (fetchLimit, context per batch, save) become testable once, not per-repair.

---

## 2. RemoteLogService — collapse the per-service sync sprawl

**Files involved:**
- `swift/ios/CarrierWave/Services/SyncService.swift` + 13 extensions
- `swift/ios/CarrierWave/Services/QRZClient.swift` + extensions
- `swift/ios/CarrierWave/Services/POTAClient.swift` + extensions
- `swift/ios/CarrierWave/Services/ClubLogClient.swift`, `EQSLClient.swift`, `LoTWClient.swift`, `HAMRSClient.swift`
- LoFi client lives in `CarrierWaveCore`/`CarrierWaveData`

**Friction:** No single interface for "a remote QSO service." `SyncService` orchestrates by reaching into 7 differently-shaped clients; `+UploadClubLog` / `+UploadEQSL` / `+POTAUploadDedup` exist because there's no common adapter shape (`upload(qsos)`, `download(since:)`, `confirmations(since:)`, `credentials`).

**Deletion test:** One `RemoteLogService` protocol with 7 adapters concentrates per-service oddities behind a uniform seam; `SyncService` collapses to a scheduler over `[RemoteLogService]`.

---

## 3. LoggerView is a god view, not a deepened module

**Files involved:** `swift/ios/CarrierWave/Views/Logger/LoggerView.swift` + ~20 `LoggerView+*.swift` extensions.

**Friction:** Extensions reach into a 70+ property `@State`/`@Environment` bag on the parent. Inlining every `+` file would just produce a ~1500-line file — extensions provide zero **leverage**, only file-size relief.

**Deletion test:** Extensions disappearing wouldn't concentrate complexity; the god state bag *is* the complexity.

**Direction:** Extract `LoggerInputModel` (callsign + RST + park + parsed quick entry) and `LoggerCommandExecutor` as deep modules with small interfaces.

---

## 4. Stats computation duplication

**Files involved:**
- `swift/ios/CarrierWave/Views/Dashboard/QSOStatistics.swift` + `+Streaks`
- `AsyncQSOStatistics.swift` + `+Apply` + `+Pipeline`
- `StatsComputationActor.swift` + `+Extensions`
- `Services/BragSheet/BragSheetComputationActor.swift` + 4 extensions
- `EquipmentStatsActor.swift`, `POTAAwardsActor.swift`, `SinglePassAccumulator.swift`

**Friction:** Dashboard stats and brag-sheet stats have the same shape (fetch QSO snapshot in batches → run accumulator → publish results) but no shared base.

**Direction:** A `StatsComputation<Accumulator>` actor (snapshot fetch + cooperative yielding + publish) makes the brag-sheet/dashboard split a configuration, not a duplication. `QSOStatistics` already has the right shape; the actors above it are reinventing the same loop.

---

## 5. QSOProcessingActor extensions chunk one operation

**Files involved:** `QSOProcessingActor.swift`, `+Merge`, `+DeadStateRepair`, `+OrphanRepair`, `+SessionGrouping`, `+POTAReconcile`, `+POTAGapRepair`, `+DataRepairs`.

**Friction:** Real depth (SwiftData isolation requires the actor) but extensions are stages of a single ordered pipeline that callers can't see or test individually.

**Direction:** `[QSOPipelineStage]` would make order explicit and stages testable. Lower priority — only worth it if stage-level tests are wanted.

---

## 6. Diagnostic surfaces don't compose

**Files involved:** `SyncDebugLog.swift`, `StartupProfiler.swift`, `StartupTrace.swift`, `DiagnosticsCollector.swift` + 2 extensions, `UploadDiagnosticStore.swift`, `BugReportService.swift`.

**Friction:** Three persistence models, three log surfaces. `DiagnosticsCollector` exists *because* the surfaces don't compose — it's the second adapter that proves there's a missing seam.

**Direction:** A `DiagnosticSource` protocol; bundling becomes `[DiagnosticSource].package()`.

---

## Healthy modules (do not touch)

- `ReferenceCacheSupport.swift` — small interface, three adapters (`POTAParksCache`, `SOTASummitsCache`, `WWFFReferencesCache`), real leverage.
- `QSOStatistics.swift` — pure functions over QSO arrays; the seam exists.

---

## Selected for work

**#1 — Repair Pipeline.** Cleanest win, smallest blast radius, ~12 adapters waiting.

### Locked-in decisions (grilling, 2026-05-02)

- **Two seams, not one.** `BatchedRewrite<Model>` for predicate + per-row mutation. `CrossBatchMerge<Model, Snapshot>` for collect-snapshots → match → merge. Forcing both into one interface adds dead surface to the rewrite case.
- **Live in `CarrierWaveData/Repair/`**, not the iOS target. The pattern operates on `BoundedDescriptor` + `ModelContext` and isn't iOS-specific.
- **`LaunchRepairRegistry` (today's `DataRepairService`) stays in the iOS target** as the gate runner. The seams know nothing about UserDefaults gating, keychain, or launch flow.
- **Result types are seam-fixed**, not bespoke: `BatchedRewrite.Result { scanned, mutated }` and `CrossBatchMerge.Result { snapshotsCollected, pairsFound, merged }`. Existing facades (e.g. `KIndexRepairService.RepairResult { sessionsRepaired, metadataRepaired }`) wrap two `BatchedRewrite` calls and surface per-table totals from `Result.mutated`.
- **`mutate` returns `Bool`** so `mutated < scanned` is meaningful for the Dashboard "1,247 scanned, 18 changed" UX.
- **`CrossBatchMerge` is split into `plan() → apply(_:)`** so dry-run (existing `countDuplicates()` API) is free.
- **`Snapshot` is a generic per repair**, not a `[String: AnyHashable]` bag — preserves type safety; the matcher owns the snapshot type.
- **No protocols.** Closures keep the interface narrow. Adding a `Repair` protocol would force ceremony for what's a 4-arg constructor.
- **No progress streaming yet.** Add `AsyncStream<Progress>` only when a UI need appears; today's Dashboard surfaces only post-run totals.
- **Vocabulary added to `CONTEXT.md`** at repo root: `Repair`, `BatchedRewrite`, `CrossBatchMerge`, `Repair Registry`. First entries in the file.

### Soak-test migrations done (2026-05-02)

- `KIndexRepairService` — façade over two `BatchedRewrite`s (LoggingSession + ActivationMetadata). 86 → 67 LoC.
- `PhoneSSBDuplicateRepairService` — façade over `CrossBatchMerge<QSO, PhoneSSBSnapshot>`. Match logic and field/presence absorption preserved verbatim. iOS app builds clean.

### Migrated to seams (2026-05-02, second commit)

`BatchedRewrite` façades:
- `CommentParkRefRepairService`
- `HuntingParkRefRepairService` (inline auxiliary side-effect: clear POTA upload flags)
- `DuplicateSpotNoteRepairService`
- `ActivityLogQSORepairService` (pre-fetches ActivityLog IDs once; closure captures the set)
- `ConditionsBackfillService`
- `POTAPresenceRepairService` (count + repair both, in-memory enum filter inside closure)
- `DataRepairService.repairBandCase` (inlined as a registry-side `BatchedRewrite<QSO>` call)

`CrossBatchMerge` façades:
- `ServicePresenceDeduplicationRepairService` (no-op merge; matcher picks winner, seam deletes losers)
- `TwoferDuplicateRepairService` (matcher delegates to `TwoferMatcher`; flattens N-loser groups into N MergeActions)

### Not migrated — irregular shape

- **`WPMBackfillService`** — fix needs to write to `ActivationMetadata` keyed by `(parkRef|date)` from `LoggingSession` data, with row creation when the metadata doesn't exist. Doesn't fit row-local `BatchedRewrite` cleanly. Has its own unbounded-fetch performance issue worth a separate pass.
- **`POTASplitRepairService`** — scan-and-spawn pattern (one session → N sessions). Neither rewrite nor merge.

### Open follow-ups

1. Run KIndex / PhoneSSB / Twofer / SP-Dedup tests on device to confirm no behaviour regression.
2. Pre-existing blocker: `WhatsNewTests.swift` fails to compile against macOS SDK 26.2 (Bundle subclass init + `lastSeenKey` access level). Blocks `swift test` at the package level. Unrelated to this work.
3. Decide whether to revisit `WPMBackfillService` and `POTASplitRepairService` with new seams (`BackfilledRowFromSource<Source, Target>`? `ScanAndSpawn<Model>`?) — each is a one-off; may not be worth it.
