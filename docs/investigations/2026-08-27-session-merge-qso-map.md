# Session merge doesn't regenerate the QSO map

**Date:** 2026-08-27
**Report:** "If you merge 2 sessions it doesn't regen the QSO map" (iOS feedback).
User confirmed the stale surface is the **session detail map preview**.

## Symptom

After merging session A into session B, the QSO map in B's detail view keeps
showing only B's original contacts. The QSO list/stats in an already-open
detail view are stale too; the map is just the most visible casualty.

## Root cause

`SessionDetailView` loads its QSOs exactly once, in `.task { await loadQSOs() }`.
For data that changes underneath a live detail view it relies on the
`.sessionQSOsDidChange` notification — but that notification was only posted by
the ADIF session import path (`ImportService+Session.swift`). Session merge
(`LoggingSessionManager.mergeSessions`) reassigns QSOs in both cw-store (Rust
`merge_sessions`) and SwiftData, and the Sessions *list* reloads explicitly,
but no signal ever reached a live detail view, so its `qsos` state — and the
map preview derived from it — never regenerated.

Two secondary staleness sources compounded it even when `qsos` did reload:

1. The map preview camera was framed in a one-shot `.task`, so new pins could
   land outside the visible region with no re-frame.
2. The full-screen map destination used the `POTAActivation` value struct
   frozen at navigation time (`activation.qsos` snapshot), not the live QSO
   state.

## What was ruled out

- Data layer: Rust `merge_sessions` and the Swift mirror both correctly
  reassign QSOs, expand bounds, fold counts, and delete the source; a fresh
  fetch by target session id returns the union.
- Sessions list caches (`qsosBySessionId` / `activationsBySessionId`): rebuilt
  by `loadSessions()` immediately after merge.
- Map tab (`QSOMapView`) and share renderers: computed from live data.

## Fix

- `LoggingSessionManager+SessionManagement.swift`: `mergeSessions` now posts
  `.sessionQSOsDidChange` with the target session id (via `defer`, so both the
  Rust-delegated and fallback paths fire it). `SessionDetailView` already
  subscribes and reloads QSOs + statistics.
- `SessionDetailView+Map.swift`: camera task keyed on the mappable QSO count so
  the preview re-frames when the session's QSOs change.
- `SessionDetailView+Insights.swift`: the full-screen map destination regroups
  a live `POTAActivation` from the current `qsos` (falling back to the pushed
  snapshot) so tapping the preview also shows the merged set.

## Platform coverage

- **iOS:** fixed above.
- **Android / macOS Sweep:** no session-merge UI exists; nothing to fix.
- **Rust core:** `merge_sessions` already emits `FfiStoreChange` notifications
  for store-change listeners — the cross-platform signal is in place for when
  Android grows a merge surface.
