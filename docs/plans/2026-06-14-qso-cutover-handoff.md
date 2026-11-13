# QSO Rust-Store Cutover — Handoff

**Date:** 2026-06-14
**Branch:** `main`
**Companion docs:** [design/spec](2026-06-14-qso-rust-store-cutover-design.md) · [Plan A](2026-06-14-qso-cutover-plan-A-infrastructure.md) · [rust-core handoff](2026-06-13-rust-core-handoff.md) · [importer design](2026-06-14-swiftdata-import-design.md)

The "pick it up from here" doc for the Phase-4 consumer cutover (replacing
SwiftData reads with the Rust `cw-store`). The design explains *why/what*; this
explains *what's done, what's next, and what to watch*.

---

## TL;DR

**Sub-project A (infrastructure + count) is DONE and verified on device.** The full
dual-write → flagged-read → parity pipeline works end-to-end behind a hidden,
off-by-default experiment. SwiftData remains the system of record; the Rust store
is a read mirror only. Two real bugs were caught in review/on-device and fixed
(below). The big remaining work is the Logbook list itself, split into B and C.

The cutover was decomposed during planning into three sequenced sub-projects:

- **A — infrastructure + count** ✅ done (this handoff).
- **B — `.cwquery` → Rust/SQLite query compiler + ServicePresence live mirror**
  ✅ done 2026-06-15 (commits `3e977f4b`..`e611e4c6`). Full-DSL AST→SQL compiler in
  `cw-store/query` at parity with the Swift `QueryCompiler`, proven by a 68-query
  Swift↔Rust corpus acceptance test (`QueryParityTests`). `service_presence` is now
  live-mirrored (drives `synced:`/`pending:`). `RustQSOReadSource.page(query:)` /
  `count(query:)` are the seam C consumes (returns `QSORowSnapshot`). See
  [B design](2026-06-15-qso-cutover-B-query-compiler-design.md) +
  [B plan](2026-06-15-qso-cutover-B-query-compiler-plan.md). Notes: a real
  frequency-unit parity bug (Swift MHz vs cw-store kHz) was caught by the gate and
  fixed; a pre-existing P1 lexer infinite-loop on unrecognized chars (`%`/`@`/…) was
  fixed in **both** `cw-domain` and `CarrierWaveCore`. The `CwFfi.xcframework` binary
  is gitignored — Xcode Cloud / other machines must run
  `rust/cw-core/scripts/build-xcframework.sh` to pick up the new FFI.
- **C — `LogsListView` on snapshots + Rust list read** ✅ done 2026-06-16 (commit
  `3b8d2fa0`; see [C handoff](2026-06-16-qso-cutover-C-handoff.md)). The list renders from
  `QSORowSnapshot` via a `LogbookSnapshotSource` routed by `cwStoreQSOMode`, with
  id-bridged delete/select/group (`LogbookIDBridge`) and a mirror-drain barrier in `on`.
  **All three sub-projects (A, B, C) are now complete.**

## What shipped in A (commits on `main`)

| Commit | What |
|---|---|
| `6635525d` | `cw-store` `delete_qso(id)` (idempotent) |
| `364974e3` | `cw-ffi` `delete_qso` fires `notify(.Delete)` |
| `ab1405e0` | regenerated `CwFfi.xcframework` + bindings |
| `2c14a3eb` | `CwStoreProvider` — shared long-lived `FieldStore` (App Group + device key) |
| `88276fcc` | hidden `ExperimentalFeature.rustStoreQSO` + `CwStoreQSOMode {off,shadow,on}` |
| `33057e39` | `CwStoreMirrorActor` — serial off-main dual-write |
| `ae4c090c` | `QSOReadSource` (count) + `QSOParityProbe` |
| `87a6062f` | `CwStoreMirror` — observe `ModelContext` saves, dual-write QSO changes |
| `00211f77` | route mirror writes through the off-main actor (fix #1) |
| `aa5d3a33` | wire mirror lifecycle + Data Migration UI (mode picker, parity button) |
| `a04201c0` | make `CwStoreMirror` thread-safe — fix background-context crash (fix #2) |

**Files of note:**
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/` — `CwStoreProvider`, `QSOReadSource` (+ `CwStoreQSOMode`), `QSOParityProbe`.
- `swift/ios/CarrierWave/Services/RustStore/` — `CwStoreMirror`, `CwStoreMirrorActor`.
- `swift/ios/CarrierWave/Views/Settings/ExperimentsView.swift` — Data Migration controls.
- `swift/ios/CarrierWave/CarrierWaveApp.swift` — `applyQSOMirrorMode` lifecycle.

## How to exercise it

Enable the hidden **"QSO Rust Store"** experiment (Settings → Experiments). In
Data Migration, set the mode and use **Run QSO Parity Check**:
- `off` — today's behavior; mirror not observing.
- `shadow` — mirror dual-writes on every save; reads stay on SwiftData. Parity
  check compares raw counts (expect `QSO parity OK: N rows.`).
- `on` — same writes; reads route through the seam.

Enabling shadow/on runs (in order) **start mirror → idempotent reconcile import**.
Flip to `off` for instant rollback (SwiftData never written by the Rust path).

## Two bugs caught (don't reintroduce)

1. **Synchronous main-thread writes.** The first mirror wrote to the Rust store
   synchronously inside the `queue: nil` `didSave` handler — fine for the test, but
   a bulk import (thousands of QSOs in one save) would hang the UI. Fixed: writes
   go through the serial `CwStoreMirrorActor` off-main; `drain()` awaits the
   dispatched task (`00211f77`).
2. **`MainActor.assumeIsolated` crash on background-context saves.** The observer
   uses `object: nil`, so it fires on the executor of *whatever* `ModelContext`
   saves — including background contexts (sync journal, repairs, imports).
   `assumeIsolated` off-main is a hard crash; adding a QSO on device hit it. The
   in-memory test only saved on the main context, so it passed. Fixed (`a04201c0`):
   `CwStoreMirror` is now `nonisolated final class … @unchecked Sendable`, handles
   each save on the arriving thread, **projects on the saving context's own
   executor** (so `SwiftDataStoreImporter.project/uuid/unix/jsonStringArray` are
   `nonisolated`), buffers value types under an `NSLock` keyed by `ObjectIdentifier(context)`,
   and hands them to the actor. There is now a **background-context regression
   test** (`CwStoreMirrorTests.testBackgroundContextSaveMirrorsWithoutAssumingMainActor`).

   **Lesson for the rest of the cutover:** any `ModelContext`-save observer must be
   thread-agnostic. In-memory tests that only save on `mainContext` will *not*
   catch off-main crashes — add a background-context test.

## Watch list / known seams (resolve as the cutover grows)

- **Two `FieldStore` opens of the same file.** `CwStoreProvider.shared` (mirror +
  reads) and `CwStoreImportCoordinator.runIfNeeded` (the reconcile import) each
  call `FieldStore.open` on the same `cw-store.db`. It works today, but two writer
  handles to one SQLCipher file is a latent hazard — consolidate the importer onto
  `CwStoreProvider.shared` when convenient.
- **`changedModelsArray` vs `insertedModelsArray` overlap.** The mirror upserts
  both; upsert is idempotent so duplicates are harmless, but be aware.
- **Metadata pseudo-modes.** Count parity is raw (both sides count all rows,
  mirror stores verbatim). When list reads land (C), the Rust read path + snapshot
  MUST apply the same `QSOMode.isMetadata` filter the Logbook uses, or parity shows
  false mismatches.
- **Read-after-write in `on` mode.** The read path must `await mirror.drain()`
  before a Rust read so a just-saved row isn't missed (the barrier exists; wire it
  in when reads actually switch to Rust).

## Next steps, in order

1. **Brainstorm sub-project B** — `.cwquery` → Rust/SQLite query compiler. The
   Logbook DSL (`ParsedQuery` → SwiftData `#Predicate` or in-memory `((QSO)->Bool)`)
   is arbitrary; the Rust `QsoFilter` is bounded (`callsign_prefix/band/mode/since`).
   Decide the query AST, field/operator → SQL mapping, and parity-vs-Swift testing.
   This is the long pole.
2. **Plan + build C** — refactor `LogsListView` to render from a list snapshot with
   id-bridged delete/select/group, wired to A's `QSOReadSource` and B's compiler.
3. **Then**, once reads are trusted across entities, the write-cutover (retire
   SwiftData as system of record) and macOS Sweep lockstep — both explicitly out of
   scope so far.

## Out of scope (unchanged this slice)

Cutting SwiftData writes; all non-QSO entities; stats/map/aggregation reads;
deleting SwiftData; macOS Sweep wiring.
