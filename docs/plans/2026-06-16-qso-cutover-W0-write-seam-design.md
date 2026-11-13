# QSO Rust-Store Cutover — Sub-project W0: Write Seam + Inline Projection — Design

**Date:** 2026-06-16
**Status:** Draft (design approved; spec under review)
**Phase:** 4 (consumer cutover — write side, foundation slice)
**Companion docs:** [cutover design/spec](2026-06-14-qso-rust-store-cutover-design.md) · [C handoff](2026-06-16-qso-cutover-C-handoff.md) · [rust-core handoff](2026-06-13-rust-core-handoff.md)

---

## Goal

Begin the **write-cutover**: make the Rust `cw-store` authoritative for QSO **writes**
(not just reads), while keeping SwiftData alive as a downstream **sync adapter** so the
existing `CloudSyncJournalEngine` + CloudKit keep propagating changes across devices
unchanged. This is the foundation slice (W0) of the write-side epic — it builds the
write seam and the echo-control primitive that the later slices (W1 interactive writes,
W2 bulk paths) reuse, and proves the whole loop end-to-end on the **minimal** write:
`hide`/`unhide`.

SwiftData is **not** deleted in this slice. Fully retiring SwiftData and replacing
CloudKit with the server-side `cw-sync` is Phase 5, gated on the OAuth2 auth overhaul,
and explicitly out of scope here.

Success = on a real device, with the hidden **QSO Rust Store** experiment in `on` mode:
hide a QSO → it leaves the Logbook (served from cw-store since slice C) → the hidden
state propagates to a second device via CloudKit → flip the experiment to `off` → the
QSO is still hidden in SwiftData. Parity sweep reports zero drift throughout. Flip to
`off` is instant rollback.

## Locked decisions (carried from earlier reviews + this one)

- **Cutover target for the slice (chosen 2026-06-16):** invert authority for writes;
  SwiftData demoted to a downstream sync adapter. Not a full SwiftData deletion (that is
  Phase 5).
- **Write-entry-point scope of the epic:** all write paths (interactive + bulk). W0
  itself only cuts over `hide`/`unhide`; `logQSO`/edit/import/bulk-delete migrate in
  W1/W2.
- **Inversion depth (chosen 2026-06-16):** full write unwind is the end-state — app code
  stops constructing/holding live `QSO` `@Model` objects on the write path. That unwind
  is the W1/W2 consumer refactor; W0 lays the seam it routes through.
- **Mechanism (decided this review):** **inline projection at the seam**, NOT an async
  reverse mirror. See rationale below.

## Why inline projection, not an async reverse mirror

The W0 sequencing proposal originally called for an async cw-store→SwiftData reverse
mirror driven by `FieldStore.changes(for:)`. Inspecting the Rust observation API
disproved that approach:

- **The change notification is coarse.** `FfiStoreChange` carries only
  `{ table, kind }` (`cw-ffi/src/observation.rs`), with **no row id**. An async reverse
  mirror reacting to "the Qso table changed" cannot identify *which* QSO changed, so it
  would have to full-reconcile the table on every write — a flat violation of the
  performance rules (no full scans; max 1,000 QSO objects in memory; main-thread impact
  must be O(1)).
- **The seam already holds the payload.** When the seam writes a QSO to cw-store it has
  the exact canonical value in hand. It can project that same change into SwiftData
  **inline**, synchronously and in order, with no observation, no AsyncStream race, and
  no read-after-write drain barrier for seam-originated writes.
- **Nothing writes cw-store outside the seam** in the W0–W2 world. Inbound CloudKit
  changes arrive *through* SwiftData (then `CwStoreMirror` carries them into cw-store), so
  SwiftData already has them — there is nothing to project back. The only future writer
  that bypasses the seam is Phase 5's `cw-sync`, and Phase 5 deletes SwiftData anyway.

Conclusion: an async reverse mirror is never actually needed for this epic, and is
impractical given the coarse notification. W0 uses inline projection.

(Separately confirmed during this review: `delete_qso` already fires
`FfiChangeKind::Delete` with a passing test — `cw-ffi/src/lib.rs:455`,
`observation.rs:delete_qso_fires_delete_notification`. The "expose `notify(.Delete)`"
item flagged in the rust-core handoff is **already done**; W0 does not need it.)

## Architecture

Two units plus one new primitive, all gated behind the existing
`ExperimentalFeature.rustStoreQSO` + `@AppStorage cwStoreQSOMode` (off|shadow|on):

```
QSOWriteSink (seam)                       CwStoreMirror (existing)
  off/shadow → SwiftData-first (today)      observes ModelContext save on ALL contexts
  on         → cw-store FIRST (canonical)   projects QSO/ServicePresence → cw-store
               then project → SwiftData
               (mirror suppressed for          ── retained for INBOUND CloudKit path
                this save)                      ── SKIPS capture while seam-origin flag set
```

### `QSOWriteSink` — the write seam

A `@MainActor` seam that funnels QSO mutations and routes by `cwStoreQSOMode`. W0
implements exactly the operation `hide`/`unhide` needs; the protocol is shaped to grow
into `upsert`/`delete` for W1/W2 but those are **not** implemented in W0 (YAGNI).

```swift
@MainActor
protocol QSOWriteSink {
    /// Set the hidden flag on an existing QSO (and clear ServicePresence upload flags
    /// when hiding). Routed by cwStoreQSOMode.
    func setHidden(_ qso: QSO, hidden: Bool) throws
}
```

- `off` / `shadow`: today's behavior — mutate the live `QSO` (and its `servicePresence`),
  `try modelContext.save()`. `CwStoreMirror` propagates to cw-store as it already does.
- `on`:
  1. Write cw-store **first**: upsert the QSO row with `isHidden` set (and the affected
     `ServicePresence` rows with `needsUpload = false`) via the existing FFI upsert. This
     is the canonical, gatekeeping write — if it throws, abort and do not touch SwiftData.
  2. On success, **project into SwiftData**: raise the seam-origin flag, mutate the live
     `QSO`/`ServicePresence`, `try modelContext.save()`, lower the flag. This save exists
     only so `CloudSyncJournalEngine` marks the rows dirty and pushes the hidden state to
     CloudKit. `CwStoreMirror` is suppressed for it (step below), so cw-store is written
     exactly once.

The existing `LoggingSessionManager.hideQSO(_:)` / `unhideQSO(_:)` delegate to the seam
instead of mutating + saving directly. Their non-store side effects (session counter
decrement, Live Activity, widget) stay where they are — W0 does not touch the
`QSO`-object coupling; that is W1.

### Echo control — the seam-origin flag

The one new primitive. A thread-safe flag, raised by the seam around its inline SwiftData
save in `on` mode, that `CwStoreMirror` honors:

- The seam sets the flag immediately before `modelContext.save()` and clears it
  immediately after, on the main context. `CwStoreMirror`'s `willSave`/`didSave` fire
  **synchronously on that same thread** during `save()`, so the flag is observed
  deterministically for exactly that save.
- When the flag is set, `CwStoreMirror.capture(from:)` skips QSO and ServicePresence
  changes for that context (returns them empty), so the seam-origin save does **not**
  bounce back into cw-store.
- Storage: a flag guarded by `CwStoreMirror`'s existing `NSLock` (the class is already
  `@unchecked Sendable` with an `NSLock`), exposed via a tiny set/clear API the seam
  calls. Not `nonisolated(unsafe)` (perf rule).

Why only `CwStoreMirror` is suppressed, not `CloudSyncService`: a local hide **should**
propagate to CloudKit, so `CloudSyncService`'s `didSave`-driven journaling must run
normally. Only the redundant SwiftData→cw-store echo is suppressed.

### What stays exactly as-is

- **Inbound CloudKit → SwiftData → cw-store.** `CloudSyncJournalEngine+Inbound` applies
  remote changes to SwiftData under its own `isApplyingInbound` guard (which suppresses
  `CloudSyncService` re-journaling, not `CwStoreMirror`). The seam-origin flag is **not**
  set for inbound applies, so `CwStoreMirror` carries the remote change into cw-store as
  it does today. Remote hides reach the canonical store unchanged.
- **Reads.** Slice C already serves the Logbook from cw-store in `on` mode. Seam writes
  are synchronous, so a list refresh after a hide sees the change immediately — no drain
  barrier needed for seam writes. The existing `CwStoreMirror.drain()` barrier still
  covers the async inbound path.

## Data flow

**Local hide (`on` mode):**
```
user hides QSO
  → QSOWriteSink.setHidden(qso, true)
      → cw-store upsert (isHidden=true, ServicePresence.needsUpload=false)   [canonical]
      → raise seam-origin flag
      → SwiftData: qso.isHidden=true, presence.needsUpload=false, save()
          → CwStoreMirror.willSave/didSave: flag set → SKIP (no echo)
          → CloudSyncService.didSave (debounced) → journal dirty → CloudKit
      → lower seam-origin flag
  → Logbook refresh reads cw-store → QSO gone
```

**Inbound hide from another device (`on` mode):**
```
CloudKit journal fetched
  → CloudSyncJournalEngine+Inbound applies → SwiftData save() (isApplyingInbound=true)
      → CwStoreMirror.didSave: flag NOT set → projects QSO → cw-store   [canonical updated]
      → CloudSyncService suppressed by isApplyingInbound (no ping-pong)
  → Logbook refresh reads cw-store → QSO gone
```

## Failure semantics & rollback

- **cw-store write fails:** abort, SwiftData untouched, log to the in-app diagnostics
  surface (same surface the importer/parity probe use). The hide does not take effect;
  the user can retry. SQLCipher local write failure is rare (disk-full/corruption class).
- **SwiftData save fails after cw-store succeeded:** divergence — cw-store has the hide,
  SwiftData does not, so CloudKit won't propagate it and a flip to `off` would "lose" the
  hide from the SwiftData view. Logged as a divergence; the existing parity sweep detects
  it. This is the same risk class slice C accepted, behind an off-by-default experiment.
  (Note today's `hideQSO` already uses `try?` and silently swallows SwiftData save
  errors; W0 is strictly more observable.)
- **Rollback:** flip `cwStoreQSOMode` to `off`. Writes immediately return to the
  SwiftData-first path; SwiftData has been kept current the whole time, so there is
  nothing to reconcile.

## Testing

- **Rust:** no new work — `delete_qso` delete-notify is already covered;
  `upsert_qso`/`delete_qso` round-trips exist.
- **Swift unit (in-memory SwiftData + a real cw-store):**
  - `on` mode: `setHidden(qso, true)` writes the canonical hidden state to cw-store, the
    SwiftData row reflects it, and `CwStoreMirror` was suppressed (assert exactly one
    cw-store mutation, not a re-entrant echo — e.g. observe upsert count / drain then read).
  - `off` mode: behavior identical to today (SwiftData mutated; `CwStoreMirror` performs
    the cw-store write).
  - Echo guard: a save performed with the seam-origin flag set produces **no**
    `CwStoreMirror` capture; a save with the flag unset (inbound-style) still mirrors to
    cw-store.
  - Unhide round-trips symmetrically.
- **Parity:** after a hide in `on` mode, the existing **Run QSO Parity Check** /
  **Saved-Query Parity Sweep** report zero drift between SwiftData and cw-store.
- **Device:** enable `on`; hide a QSO → leaves the Logbook; confirm the hidden state
  reaches a second device via CloudKit; flip to `off` → still hidden in SwiftData;
  unhide → reappears.

## Scope

**In (W0):**
- `QSOWriteSink` seam with `setHidden` only, routed by `cwStoreQSOMode`.
- Inline cw-store-first projection for `on` mode (canonical write + SwiftData replica).
- The seam-origin echo-suppression flag on `CwStoreMirror`.
- `LoggingSessionManager.hideQSO`/`unhideQSO` delegated through the seam.
- Unit + parity + device tests above.

**Out (deferred):**
- `logQSO`, `QSOEditSheet.save`, hard-delete → seam (W1), and the consumer unwind off
  live `QSO` objects (`QSOLedger`, widget, Live Activity, `processActivityForQSO`,
  `.didLogQSO`).
- ADIF import, LoFi sync import, group/bulk delete → seam (W2).
- Any async reverse mirror (shown unnecessary above).
- Adding a row id to `FfiStoreChange` (only an async mirror would need it).
- Deleting SwiftData / replacing CloudKit with `cw-sync` (Phase 5).
- macOS Sweep (later, same pattern).
