# QSO Write-Cutover — Handoff (W0 + W1 + W2)

**Date:** 2026-06-17
**Branch:** `main`
**Companion docs:**
[W0 design](2026-06-16-qso-cutover-W0-write-seam-design.md) · [W0 plan](2026-06-16-qso-cutover-W0-write-seam-plan.md) ·
[W1 design](2026-06-16-qso-cutover-W1-interactive-writes-design.md) · [W1 plan](2026-06-16-qso-cutover-W1-interactive-writes-plan.md) ·
[W2 design](2026-06-16-qso-cutover-W2-bulk-writes-design.md) · [W2 plan](2026-06-16-qso-cutover-W2-bulk-writes-plan.md) ·
[cutover decomposition](2026-06-14-qso-rust-store-cutover-design.md)

The "pick it up from here" doc for the **write** side of the QSO Rust-store cutover.
The read side (sub-projects A/B/C) shipped earlier; this covers the write seam.

---

## TL;DR

The Rust `cw-store` is now **authoritative for QSO writes** in `on` mode for every
**interactive and bulk** QSO write path — plus the view-layer **restore/unhide** paths
and the **top-level ADIF + LoFi imports** (W3) — while SwiftData remains the system of
record for **CloudKit sync** (the `CloudSyncJournalEngine` is untouched). All writes
route through a single `QSOWriteSink` seam, gated by the hidden, off-by-default
`cwStoreQSOMode` experiment (`off` / `shadow` / `on`).

Still deliberately **deferred** (documented below, not silently skipped): the
**in-place-update imports** (session-targeted ADIF, QRZ/POTA redownload) cw-store-first —
they need an update-capture refactor and stay mirror-followed for now — and the
**consumer-snapshot unwind** (app code still holds live `QSO` `@Model` objects). Neither
is a correctness gap.

## Mode semantics (recap)

| Mode | Seam | QSO writes | cw-store population | User-visible |
|------|------|-----------|---------------------|--------------|
| `off` | not built | legacy SwiftData save | none | today's behavior |
| `shadow` | built | plain SwiftData save | `CwStoreMirror` dual-writes (async) | none |
| `on` | built | **cw-store first**, then mirror-suppressed SwiftData save | seam (canonical) | Logbook + writes served from cw-store |

Flip to `off` = instant rollback. SwiftData is never abandoned; it is the CloudKit bridge.

## Architecture / where things live

**Seam + plumbing (app target, `swift/ios/CarrierWave/Services/RustStore/`):**
- `QSOWriteSink.swift` — the seam (`@MainActor struct`). Methods:
  - `setHidden(_:hidden:in:)` — mutates `isHidden`/clears `needsUpload`, then delegates to `upsert`.
  - `upsert(_:in:)` — single QSO insert/update: cw-store upsert (QSO + its ServicePresence) first, then mirror-suppressed save (`on`); plain save otherwise.
  - `upsertBatch(_:in:)` / `deleteBatch(_:in:)` — batch equivalents (delete removes presences + QSO from cw-store first, then `context.delete` + suppressed save).
  - private `writeUpsertToStore(_:)`, `applyHiddenInMemory(_:hidden:)`.
  - static routing helpers `commitUpsert` / `commitUpsertBatch` / `commitDeleteBatch` (route through `QSOWriteSinkRegistry.current`, else fall back to a plain SwiftData save/delete).
  - `QSOWriteSinkRegistry` — `@MainActor enum` holding `static var current: QSOWriteSink?`.
- `CwStoreMirror.swift` — the echo-suppression primitive: `beginSeamWrite()`/`endSeamWrite()` (depth-counted, `NSLock`-guarded `seamWriteDepth`); `capture(from:)` returns empty while a seam write is in flight. Still fully active for inbound CloudKit → SwiftData → cw-store and (in `shadow`) for all dual-writes.
- `CwStoreWriteLog.swift` — `@MainActor` in-memory ring buffer (cap 50) for write-path failures; surfaced in Settings → Experiments → **Data Migration**.

**Mode accessor:** `CwStoreQSOMode.current` (`swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift`) reads the flag from `UserDefaults` for non-View code.

**Wiring:** `CarrierWaveApp+QSOMirror.swift` — `applyQSOMirrorMode` builds + registers the mirror **and** the seam (sharing one `FieldStore`) for `on`/`shadow`, clears both on `off`. Import/mirror-setup failures now log to `CwStoreWriteLog`.

## Write paths — routed vs. deferred (in `on` mode)

**Routed cw-store-first through the seam:**
| Path | Site |
|------|------|
| hide / unhide | `LoggingSessionManager+QSOManagement.hideQSO`/`unhideQSO` (W0) |
| log a new QSO | `LoggingSessionManager+QSOManagement.insertAndFinalize` (W1) |
| edit a QSO | `QSOEditSheet+Save.save` (W1) |
| bulk hide | `LogsListView+BulkDelete.softDeleteQSOs` (W2) |
| group into session | `LogsListView+GroupSession.createSessionFromSelection` (W2) |
| "Delete All Hidden" (hard delete) | `AllHiddenQSOsView.permanentlyDeleteAllQSOs` (W2) |
| restore / restore-all (unhide) | `AllHiddenQSOsView.restoreQSO`/`restoreAllQSOs` (W3) |
| ADIF import (top-level) | `ImportService.importADIF(content:)` via `commitImportedQSOs` (W3) |
| LoFi sync import | `ImportService.importFromLoFi` via `commitImportedQSOs` (W3) |
| session-targeted ADIF import | `ImportService.importADIFIntoSession` (inserts + adopted rows) via `commitImportedQSOs` (W3) |
| QRZ / POTA redownload | `ImportService+External` (inserts + enriched rows) via `commitImportedQSOs` (W3) |

All follow the same shape: mutate/insert in SwiftData → `commit*` → on throw `rollback()` + `CwStoreWriteLog.record` + early-return. External side effects (widget, Live Activity, `.didLogQSO` re-page, optimistic row removal) fire **after** a successful commit so a failure can't leave half-applied UI/data. `commitImportedQSOs` commits in bounded chunks (500) with a `Task.yield()` between them so a large import can't block the main thread on one giant cw-store write + save, then flushes any non-QSO leftover (e.g. LoFi activation metadata, session counter). The in-place-update imports surface their mutated rows through `QSOProcessResult.updated([QSO])` so adopted/enriched existing QSOs ride the cw-store-first batch instead of being swallowed by the suppressed seam save.

**NOT routed — mirror-followed in `on` mode (correct, but SwiftData-first):**
| Path | Site | Why deferred |
|------|------|--------------|
| edit callsign-lookup enrichment | `QSOEditSheet+Save.refreshCallsignLookup` | best-effort async secondary save; mirror-covered |

**Note (W3):** the W2 deferral rationale that imports "run on background `ModelContext`s" was inaccurate for the *write* path — `ImportService` is `@MainActor` and inserts/saves on the **main** context (only the dedup-key *read* scan uses a background context). So the existing `@MainActor` seam routes them directly; no background-safe variant was needed. With the `QSOProcessResult.updated([QSO])` capture, every import write path (top-level ADIF, LoFi, session-targeted ADIF, QRZ/POTA redownload) is now cw-store-first in `on` mode.

`CwStoreMirror` is built to observe background-context saves (proven by
`testBackgroundContextSaveMirrorsWithoutAssumingMainActor`), so these paths still reach
cw-store — only the cw-store-first **authority/ordering** is deferred, not correctness.

## Verification status

- **Unit:** `QSOWriteSinkTests` — 9 tests (W0 hide/unhide/suppression, W1 upsert new + edit, W2 upsert/delete batch). W3 adds `ImportServiceTests.testOnModeImportRoutesToCwStore` (an `on`-mode ADIF import lands its rows in cw-store via the seam). The W0 tests double as a regression guard for the `setHidden`→`upsert` refactor; the restore paths reuse `setHidden`/`commitUpsertBatch`, already covered.
- **Build:** all routing edits `xc build`-clean.
- **Test execution this session: BLOCKED by environment, not code.** Device (`theseus`) `xc test-unit` failed the *entire* `ImportServiceTests` class — including untouched tests like `testImportSingleQSO` — with `SwiftDataError.loadIssueModelContainer` plus a "Lost pending connection to the test runner" cascade. The Simulator run never executed: the test host app `com.jsvana.FullDuplex` returns `RequestDenied`/`launch-failed` on launch (consistent with the gitignored `CwFfi.xcframework` lacking a simulator slice on this checkout). Re-run the suite on a working setup to confirm green.
- **On-device smoke: NOT yet done** for the new write paths. See next steps.

## Decisions worth remembering

1. **Inline projection, not an async reverse mirror.** `FfiStoreChange` carries no row id, so an async cw-store→SwiftData mirror would need a full reconcile per change. The seam already holds the payload, so it projects inline. (W0 design.)
2. **`setHidden` delegates to `upsert`** (W1 refactor). Consequence: `upsert` writes **all** of a QSO's ServicePresence rows to cw-store (W0's hide-specific path only touched `needsUpload` ones). Functionally an improvement (cw-store presences stay fully in sync); broader than W0's original wording.
3. **Consumer-snapshot unwind is deferred, on purpose.** Making `logQSO` return a snapshot and moving `QSOLedger`/widget/Live Activity/`processActivityForQSO`/`.didLogQSO` onto the id-bridge is *not required for write authority* and is the riskiest refactor (contact-logging hot path + upload-triggering activity detection). It belongs in the SwiftData-removal slice.

## Next steps (ordered)

1. **On-device smoke of the write paths (highest priority).** With the experiment on and mode `on`: log a new QSO, edit one, bulk-hide a selection, group into a session, "Delete All Hidden", **restore a hidden QSO + Restore All**, and **import an ADIF file + run a LoFi sync**. Confirm each reflects in the cw-store-served Logbook and run **Settings → Experiments → Data Migration → Run QSO Parity Check** (expect OK). Ideally confirm CloudKit still propagates to a second device, then flip `off` and confirm state persists in SwiftData. (Also re-run the unit suite once the runner/xcframework-slice issue above is resolved.)
2. ~~**Route the restore (unhide) paths.**~~ **DONE (W3).** `AllHiddenQSOsView.restoreQSO` routes through `QSOWriteSink.setHidden(…, hidden: false, …)`; `restoreAllQSOs` batch-unhides via `commitUpsertBatch` (fetch-from-0 per batch since restored rows leave the `isHidden` predicate).
3. ~~**Imports cw-store-first.**~~ **DONE (W3).** All import write paths route through the `@MainActor` seam via `commitImportedQSOs` (bounded 500-row chunks + `Task.yield`): top-level `importADIF(content:)`, `importFromLoFi`, `importADIFIntoSession`, and QRZ/POTA redownload. The in-place-update paths surface their mutated rows via `QSOProcessResult.updated([QSO])` so adopted/enriched existing QSOs ride the cw-store-first batch. (True off-main batching — background `ModelContext` + a `nonisolated` seam writer sharing the `FieldStore` mutex — is still a future option, folded into the SwiftData-removal slice; not needed for write authority.)
4. **Consumer-snapshot unwind** — `logQSO` returns a `QSORowSnapshot`/id; migrate `QSOLedger`, widget, Live Activity, `processActivityForQSO`, `.didLogQSO` consumers onto the slice-C id-bridge. Large; sequence with SwiftData removal.
5. **Non-QSO entities + non-list reads** — `LoggingSession`/`ServicePresence`/etc. write authority; stats/map/aggregation reads from cw-store. **Decomposition + a discovered blocker (2026-06-17):**
   - **Infrastructure that already exists:** all 13 entities have `SwiftDataStoreImporter.project(_:)` overloads, `Ffi<Entity>` records, and `FieldStore.upsert<Entity>` methods.
   - ~~**BLOCKER — entity deletes.**~~ **RESOLVED 2026-06-17.** All 12 entities now have `delete_*` over cw-ffi (id-keyed for 7; natural-key for `activation_metadata` `(park_reference, date)`, `websdr_favorite` `host_port`, `cloud_sync_metadata` `(entity_type, local_id)`), each firing `notify(.Delete)`. cw-store delete tests added (86 cw-store tests, clippy clean); `CwFfi.xcframework` regenerated (all slices) + staged; iOS build links. `CwStoreMirror` can now fully cover non-QSO entities (upserts + deletes).
   - **Per-entity shape** (mirrors the QSO A/B/C + W0–W3 arc, so each entity is itself multi-step): (a) extend `CwStoreMirror.capture` + `CwStoreMirrorActor` to observe the entity (shadow/inbound), (b) read cutover (snapshot source / query surface — most entities lack the `.cwquery`-style infra QSO got in slice B/C), (c) write seam + route the entity's write sites, (d) parity. `ServicePresence` is already live-mirrored for reads (slice B) so it's the most-advanced non-QSO entity; `LoggingSession` is the most central remaining.
   - **Net:** this step is genuinely multi-session and partly cross-language (Rust delete FFI first). It is NOT a quick follow-on.
6. **Phase 5 — retire SwiftData.** Replace CloudKit (`CloudSyncJournalEngine`) with the server-side `cw-sync` transport; gated on the OAuth2 auth overhaul. Once writes no longer need a SwiftData replica, the seam's SwiftData save + the id-bridge collapse away.
7. **macOS Sweep** — apply the same seam pattern in lockstep.

## Known seams / risks

- **Divergence on a cw-store-write failure** (disk-full/corruption class): the caller `rollback()`s SwiftData and logs to `CwStoreWriteLog`; for `deleteBatch` a mid-batch failure can leave cw-store missing rows SwiftData still has. Rare, off-by-default, caught by the parity sweep.
- **`CwFfi.xcframework` is gitignored** — `rust/cw-core/scripts/build-xcframework.sh` must run on fresh checkouts / Xcode Cloud before the Swift side builds.
- **`xc` wrapper intermittently exits non-zero with empty output** in this environment (device-connectivity quirk); `xcodebuild` confirms the real result. Not a code issue.
