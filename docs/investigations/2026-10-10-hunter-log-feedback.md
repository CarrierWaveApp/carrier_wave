# Investigation: Hunter Log feedback — vanishing QSOs, stale Sessions count, dead command buttons

**Date:** 2026-10-10
**Status:** In Progress (items 2 and 3 fixed; item 1 needs device diagnostics)
**Outcome:** Two of three reports have a confirmed code cause; the disappearing-QSO
report has no code path that explains it yet and needs a diagnostics bundle.

## Problem Statement

iOS tester feedback on the Hunter Log (Carrier Wave: Field 1.102.0):

1. While hunting, QSOs logged ~10 minutes earlier stop showing: the activator's
   spot row loses its strike-through / grey-out, and the QSO is gone from the
   contacts list in the hunter session.
2. After leaving the Hunter Log, the Sessions page card reads
   "No contacts yet today". Entering the Hunter Log and leaving again makes
   the count reappear.
3. Most command-row buttons (RBN, MAP, WX, ...) do nothing in the Hunter Log,
   and typing the command name does nothing either. HELP works.

## Findings

### 3. Command buttons — confirmed, by design gap

`QuickLogSection+Populate.executeCommand` only handles `.frequency`, `.mode`,
`.help`, `.note`, `.myCall`, `.sessionMetadata`. Everything else (RBN, HUNT,
P2P, S2S, SOLAR, WEATHER, SPOT, MAP, MANUAL, ...) hits the `default:` arm and
shows a toast: "This command is only available during an activation". The
keyboard accessory (`KeyboardAccessoryBuilder.configuredCommands`) still shows
the full `CommandRowItem` list (default `rbn,solar,weather,spot,pota,p2p`;
all ten on iPad), so the buttons are visible but inert. Typing the command
goes through the same `executeCommand`, hence identical behaviour.

The activation logger handles these via `LoggerView+Commands` →
`present(.rbn / .solar / .weather / .map)` with `RBNPanelView`,
`SolarPanelView`, `WeatherPanelView`, `SessionMapPanelView` overlays in
`LoggerView+Layout.panelOverlays`. None of those panels needs a session:
RBN takes a callsign, Weather takes a grid, Map takes a QSO array + grid.

**Fix shape:** host the same `SwipeToDismissPanel` overlays in
`ActivityLogView` (callsign = `activeLog.myCallsign`, grid =
`activeLog.currentGrid`, map QSOs = today's hunter QSOs), route
`.rbn/.solar/.weather/.map/.manual` from `QuickLogSection.executeCommand`
to them, and either implement or hide the activation-only items (SPOT, P2P,
S2S, HUNT) in the hunter accessory so no visible button is a no-op.

### 2. "No contacts yet today" — confirmed

`HunterLogStatusRow` (SessionsIntentView) renders
`manager.todayQSOCount`. That value is only ever populated by
`ActivityLogManager.refreshTodayStats()`; `loadActiveLog()` deliberately
defers it ("Today stats deferred to first refreshTodayStats() call"). The
Sessions page never calls it. It is first called by `ActivityLogView.task`,
which is why entering the Hunter Log fixes the card.

There are also **two** `ActivityLogManager` instances in the Sessions tab:
`SessionsTabView.hunterLogManager` (used when the hunter log is the default
landing, for the pending-spot route, and for the setup sheet) and
`SessionsIntentView.activityLogManager` (used by the card and its
NavigationLink). QSOs logged through a view built on one instance never
update the other's `todayQSOCount`. And `SessionsIntentView`'s manager is
`@State`, so any view-identity reset recreates it with zero stats.

**Fix shape:** pass one manager down from `SessionsTabView` into
`SessionsIntentView`, and call `refreshTodayStats()` when the manager is
created / the intent view appears and on `.didLogQSO`. Both calls are
bounded (Rust `todayStats` under `.on`, 500-row bounded fetch otherwise).

### 1. QSOs disappearing — not explained by code, diagnostics needed

Write path under the default `CwStoreQSOMode.on` (iOS default, experiment
`.rustStoreQSO` default-on): `ActivityLogManager.logQSO` →
`logQSOViaRustIfEnabled` → Rust `ActivityLogApi.logQso` writes cw-store
(`is_activity_log_qso = true`, `logging_session_id = log.id`, `qso_date` in
UTC seconds, fresh v4 id) → `FfiReflector.reflect` upserts the row into
SwiftData, mirror-suppressed → `markForUpload` → save.

Read paths that went blank are **both SwiftData**:

- Spot strike-through / grey-out: `WorkedBeforeCache.loadToday` —
  `!isHidden && timestamp >= startOfDayUTC && isActivityLogQSO`, limit 500.
  Re-runs on every spot refresh (~2 min) via `WorkedRefreshKey`.
- Recent QSOs: `ActivityLogManager.fetchRecentQSOs` —
  `loggingSessionId == activeLog.id && !isHidden && timestamp >= startOfDayUTC`,
  **limit 5**, re-fetched only after a log action.

The header count (`todayQSOCount`) under `.on` comes from **cw-store** via
Rust `todayStats`. So if the header still counts the QSO while both lists
drop it, SwiftData and cw-store have diverged for that row. That is the first
thing to confirm with the tester.

Paths examined that could remove / hide / unlink a SwiftData hunter QSO,
and why each is ruled out:

| Path | Verdict |
|---|---|
| `CwStoreReconciler` | prunes cw-store only; no-op under `.on` |
| `CwStoreMirror` | SwiftData → cw-store only; never writes SwiftData |
| CloudKit journal inbound (`applyQSOUpsert` / `applyQSODeletion`) | under `.on` + completed import routes to `QSOJournalStore` (cw-store). SwiftData path only when import never completed; merge keeps `isActivityLogQSO` via OR, `isHidden` via OR |
| Server sync replica (`SwiftDataSyncReplica`) | wired on macOS only |
| Launch repairs (`DashboardView+Repairs`, `BatchedRewrite` users) | one-shot, UserDefaults-gated; `ActivityLogQSORepairService` only sets the flag to true |
| `QSOProcessingActor+SessionGrouping` | predicates exclude `isActivityLogQSO` |
| `SessionBackfillService` | only `loggingSessionId == nil` |
| Session split / merge relink (`+RustLifecycle`, `+SessionManagement`) | scoped to a LoggingSession id |
| ADIF import `adoptExistingQSO` | relinks `loggingSessionId` (would empty Recent QSOs but not strike-throughs); only runs on an import |
| Hard deletes (`QSOWriteSink.commitDeleteBatch`) | only from AllHiddenQSOsView |
| UTC day rollover (00:00Z = 17:00 PDT) | would blank both lists and the Rust count together; does not match "re-enter and the count is back" unless logging straddled 00:00Z |

Nothing periodic in the ~10 minute window writes SwiftData QSO rows.
`SyncBackgroundRefresh` has a 15-minute floor and `SyncService` a 10-minute
timeout, but their QSO writes are `qrzLogId` only.

Edge case noticed in `ActivityLogManager+RustDelegation.logQSOViaRust`: if
`FfiReflector.reflect` throws after `context.insert(model)`, the hydrated
model stays inserted and the SwiftData fallback inserts a second copy.
Produces a duplicate, not a disappearance, but worth tightening (rollback
or delete the hydrated model before falling through).

**Ask the tester for:**

1. Whether the Hunter Log header count still includes the vanished QSOs,
   and whether they appear in Logbook / Day Summary for that day.
2. Settings → Send Diagnostics with "Include database snapshot" on
   (see `docs/investigations/2026-04-26-qso-dataloss-debug-surfaces.md`).
   Diff `database.sqlite` against `ledger-tail.adi` for the session's
   callsigns: present-but-`is_hidden`, present-with-different
   `logging_session_id`, or absent each point at a different path.
3. Settings → Experiments → cw-store write log, looking for
   "hunter logQso threw", "hunter logQso: log ... not in cw-store", or
   "hunter reflect failed".
4. Approximate UTC time of the session (rules the 00:00Z rollover in or out)
   and whether iCloud sync / Carrier Wave Sync / CW Sweep on a Mac were active.

## Files Examined

| File | Finding |
|---|---|
| `swift/ios/CarrierWave/Services/ActivityLogManager.swift` (+Persistence, +RustDelegation) | write path, stats deferral, SwiftData predicates |
| `rust/cw-core/cw-ffi/src/activity_log_api.rs` | `build_qso` sets flag + link, UTC seconds, v4 id |
| `swift/packages/CarrierWaveData/.../RustStore/FfiReflector.swift` | in-place upsert, mirror-suppressed save |
| `swift/ios/CarrierWave/Views/ActivityLog/ActivityLogView.swift`, `ActivityLogSpotsList.swift`, `RecentQSOsSection.swift` | when each list refetches; Recent list capped at 5 |
| `swift/ios/CarrierWave/Services/WorkedBeforeCache.swift` | strike-through source predicate |
| `swift/ios/CarrierWave/Views/Sessions/SessionsIntentView.swift`, `SessionsTabView.swift` | two managers, no `refreshTodayStats` on the card |
| `swift/ios/CarrierWave/Views/ActivityLog/QuickLogSection+Populate.swift` | command `default:` toast |
| `swift/ios/CarrierWave/Views/Logger/LoggerView+Commands.swift`, `LoggerView+Layout.swift`, `KeyboardAccessoryBuilder.swift`, `CommandRowSettingsView.swift` | activation handlers and the button list |
| `CwStoreReconciler`, `CwStoreMirror`, `CloudSyncJournalEngine(+Inbound,+Fields)`, `QSOJournalStore`, `CloudSyncConflictResolver`, `SyncReplica`, `DashboardView+Repairs`, `QSOProcessingActor+SessionGrouping`, `SessionBackfillService`, `LoggingSessionManager(+RustLifecycle,+SessionManagement)`, `ImportService+Session` | ruled out as periodic SwiftData writers (table above) |

## Resolution

Items 2 and 3 fixed (2026-10-10):

- `HunterPanelOverlays.swift` (new): `HunterPanelState` + the RBN / Solar /
  Weather / Map overlays, reusing the activation panel views;
  `CommandRowItem.hunterLogItems` is the set the Hunter Log can run.
  `QuickLogSection.executeCommand` routes `.rbn/.solar/.weather/.map/.manual`
  to the host via `onPanelCommand`; `.hunt` gets an informational toast.
  `KeyboardAccessoryBuilder.configuredCommands(allowed:)` /
  `CallsignTextField(allowedCommands:)` drop SPOT/HUNT/P2P/S2S from the
  hunter keyboard row.
- `SessionsIntentView.activityLogManager` is now a `@Binding` fed from
  `SessionsTabView.hunterLogManager` (one manager for the card, the
  NavigationLink, the hunter-default landing and the deep-link cover), and
  `refreshTodayStats()` runs in the intent view's `.task` and on `.didLogQSO`.

Item 1 still waits on the diagnostics bundle (see "Ask the tester for").
