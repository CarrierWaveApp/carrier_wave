# QSO Rust-Store Cutover — W1: Interactive QSO Writes (logQSO + edit) — Design

**Date:** 2026-06-16
**Status:** Draft (executing autonomously per user direction; no approval gate)
**Phase:** 4 (consumer cutover — write side, interactive writes)
**Companion docs:** [W0 design](2026-06-16-qso-cutover-W0-write-seam-design.md) · [W0 plan](2026-06-16-qso-cutover-W0-write-seam-plan.md) · [cutover design](2026-06-14-qso-rust-store-cutover-design.md)

---

## Goal

Extend the W0 `QSOWriteSink` seam to cover the remaining **interactive single-QSO
writes** — logging a new QSO (`logQSO`) and editing one (`QSOEditSheet.save`) — so that
in `on` mode the Rust `cw-store` is written **first and canonically** for these too,
consistent with hide/unhide. SwiftData stays the downstream sync adapter. Behind the same
off-by-default `cwStoreQSOMode` experiment.

## Why this is an authority/consistency slice (not "get the data there")

In `on`/`shadow` mode `CwStoreMirror` is already running and mirrors **every** SwiftData
save into cw-store (asynchronously, SwiftData-first) — except the transient window of a
seam write, which it skips. So today logQSO/edit writes already *reach* cw-store via the
mirror. W1 does not change *whether* cw-store gets the data; it changes the **ordering and
authority**: these writes become cw-store-first (canonical, abort-on-failure, immediately
fresh without a drain), matching hide/unhide. That consistency is what lets a later slice
make cw-store the sole system of record and drop SwiftData.

## Design

### Extend `QSOWriteSink` with a general upsert

```swift
@MainActor
struct QSOWriteSink {
    // existing: store, mirror, modeProvider, setHidden

    /// Commit a QSO insert/update. The caller has already inserted (for a new QSO) or
    /// mutated (for an edit) the QSO in `context`. In `on` mode this writes cw-store
    /// FIRST (the QSO and its ServicePresence rows), then saves SwiftData with the
    /// mirror suppressed. Other modes just save (the unsuppressed mirror dual-writes in
    /// `shadow`). Throws if the canonical cw-store write fails — caller must rollback.
    func upsert(_ qso: QSO, in context: ModelContext) throws {
        if modeProvider() == .on {
            try writeUpsertToStore(qso)            // canonical; throws → abort before save
            mirror?.beginSeamWrite()
            defer { mirror?.endSeamWrite() }
            try context.save()
        } else {
            try context.save()
        }
    }

    private func writeUpsertToStore(_ qso: QSO) throws {
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        for presence in qso.servicePresence {
            try store.upsertServicePresence(item: SwiftDataStoreImporter.project(presence))
        }
    }
}
```

`setHidden` is refactored to delegate to `upsert` (mutate in memory, then `upsert`), so the
two share one canonical-write/suppressed-save path:

```swift
    func setHidden(_ qso: QSO, hidden: Bool, in context: ModelContext) throws {
        applyHiddenInMemory(qso, hidden: hidden)
        try upsert(qso, in: context)
    }
```

This preserves W0 behavior: after `applyHiddenInMemory` sets `isHidden`/clears
`needsUpload`, `upsert` projects the mutated QSO + its presences → cw-store (base-set count
drops), then the suppressed save. `writeHiddenToStore`/the override-on-projection trick is
removed (no longer needed — we mutate first, and a cw-store failure is reverted by the
caller's `rollback()`, same as every other path). The existing `QSOWriteSinkTests` continue
to assert the same observable outcomes.

### Static routing helper (DRY)

```swift
extension QSOWriteSink {
    /// Route a QSO upsert through the active seam, or fall back to a plain SwiftData
    /// save when no seam is active (`off` mode / experiment disabled).
    @MainActor
    static func commitUpsert(_ qso: QSO, in context: ModelContext) throws {
        if let sink = QSOWriteSinkRegistry.current {
            try sink.upsert(qso, in: context)
        } else {
            try context.save()
        }
    }
}
```

### Route the two write sites

**`LoggingSessionManager.insertAndFinalize`** (`+QSOManagement.swift`): the QSO is already
`modelContext.insert`-ed and `markForUpload` has created its ServicePresence rows; replace
the bare `try? modelContext.save()` with the seam commit, applying the
session-counter/widget/Live-Activity side effects in the order established in W0 (model
mutations before the commit so `rollback()` reverts them; external pushes after success):

```swift
    private func insertAndFinalize(qso: QSO, session: LoggingSession) {
        modelContext.insert(qso)
        session.incrementQSOCount()
        incrementCurrentRoveStopQSOCount()
        markForUpload(qso)
        do {
            try QSOWriteSink.commitUpsert(qso, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Log QSO failed: \(error.localizedDescription)")
            return
        }
        QSOLedger.append(qso)
        NotificationCenter.default.post(name: .didLogQSO, object: nil, userInfo: ["callsign": qso.callsign])
        writeSessionToWidget(session, lastCallsign: qso.callsign)
        updateLiveActivity(lastCallsign: qso.callsign)
        Task { [weak self] in await self?.processActivityForQSO(qso) }
    }
```

On a canonical-write failure the QSO insert + counter increments are rolled back and the
post-log side effects (ledger, widget, Live Activity, activity processing) are skipped — a
clean "the contact didn't log" abort, surfaced in the Data Migration diagnostics. (Today's
`try?` silently swallows the failure and still fires every side effect against a QSO that
may not have persisted — W1 is strictly more correct.)

**`QSOEditSheet.save`** (`+Save.swift`): replace the bare `try? modelContext.save()` at the
end of `save()` with the seam commit + rollback/log:

```swift
        do {
            try QSOWriteSink.commitUpsert(qso, in: modelContext)
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Edit QSO failed: \(error.localizedDescription)")
            return
        }
```

The async `refreshCallsignLookup` secondary save (lines 124-140) is left on its plain
`try? context.save()`: it is a best-effort background enrichment, and in `on` mode the
running `CwStoreMirror` still carries that save into cw-store (it is not a seam write, so it
is not suppressed). Routing it through the seam is unnecessary and out of scope.

## Consumer unwind is deliberately deferred (not in W1)

The W0 decomposition floated W1 as "make `logQSO` return a snapshot and refactor
`QSOLedger`/widget/Live Activity/`processActivityForQSO`/`.didLogQSO` onto the id-bridge."
That consumer-snapshot-unwind is **deferred**. Rationale:

- It is **not required for write authority.** cw-store becomes canonical for the write the
  moment the seam writes it first; the app continuing to hold the live `QSO` `@Model`
  afterward does not change that.
- It is **far riskier.** Those consumers are the contact-logging hot path, the widget, the
  Live Activity, and POTA/SOTA activity detection (which triggers uploads). Rewriting them
  onto snapshots unprompted risks silent logging/upload breakage.
- It only becomes **necessary** when SwiftData is actually removed (Phase 5 territory,
  gated on the `cw-sync` server replacing CloudKit). The unwind belongs in that slice,
  where it can be verified end-to-end.

W1 therefore keeps `logQSO` returning the live `QSO` and all consumers unchanged.

## Testing

- Extend `QSOWriteSinkTests`: `on` mode `upsert` of a freshly-inserted QSO (with a
  ServicePresence) lands it in the cw-store base set and the SwiftData row, mirror
  suppressed (no duplicate); an `upsert` after a field edit propagates the changed field
  to cw-store. The existing `setHidden` tests must still pass after the delegation refactor
  (regression guard for the refactor).
- Device (deferred, same as W0): in `on` mode log a new QSO (appears in Logbook served from
  cw-store), edit it (change persists), parity check clean.

## Scope

**In:** `QSOWriteSink.upsert` + `commitUpsert`; `setHidden` refactor to delegate; route
`insertAndFinalize` (logQSO) and `QSOEditSheet.save`; tests; changelog/doc.

**Out:** hard delete, bulk/group delete, ADIF/LoFi import (all W2); the consumer-snapshot
unwind (deferred to the SwiftData-removal slice); macOS Sweep.
