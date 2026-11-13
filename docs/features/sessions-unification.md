# Sessions Unification (CAR-276)

Multi-PR initiative to unify session lifecycle across iOS (Carrier Wave: Field) and macOS (CW Sweep).

## Outcome

- Both platforms show a 2×2 intent grid as the Sessions landing: **Activate / Hunt / Casual / Contest**.
- Contest is a first-class session intent on both platforms — tapping it opens the contest picker, then a `LoggingSession` is started with `contestId` / `contestCategory` / `contestPower` set.
- A cross-platform `SessionLifecycleAPI` protocol in `CarrierWaveData/Protocols/` formalises the verbs both platforms share (`activeSession`, `pauseSession`, `resumeSession`, `finishSession`).
- iOS `LoggingSessionManager` conforms to the protocol unchanged. macOS gains `MacSessionManager` as a slim sibling implementation that doesn't carry the iOS-specific side effects (Live Activity, POTA spot polling, WebSDR auto-start, TOTA GPS tracking).
- iOS standalone Contests destinations (Activity tab row, OnAirSheet "See All" link) are removed; contests are reached only via the Sessions tab.
- macOS `SidebarItem.contests` and `ContestRootView` are retired; their operating mode lives in the Sessions panel via `ContestSessionContainer`, their browse mode via the Contest intent's picker.
- Loose macOS QSOs (`loggingSessionId == nil`) are silently backfilled at first launch of v0.13.0+ into per-UTC-day `LoggingSession` records titled `"Pre-unification log · YYYY-MM-DD"`.

## Why two implementations and not one moved class

The original PR1 plan was to move iOS's `LoggingSessionManager` into `CarrierWaveData` so macOS could use it directly. Mid-flight investigation found the iOS manager owns nine iOS-side service collaborators (Live Activity, POTA spot polling, WebSDR auto-start, TOTA GPS tracking, POTA OAuth WebView, idle timer, etc.) woven through the *core* `+SessionManagement` and `+QSOManagement` extensions — not isolated to optional add-ons. Carving them out via delegate seams was a multi-week refactor with high regression risk on iOS, and moving the class as-is would drag UIKit / ActivityKit / CoreLocation / WebKit into the shared CarrierWaveData package.

The pivot was to honour the architectural unification goal via a **protocol contract** (`SessionLifecycleAPI`) with **two implementations**. Each platform's concrete type stays honest about its feature surface; shared code (and shared tests) can speak to either via the protocol.

## PR sequence

| PR | Hash | Branch | Summary |
|----|------|--------|---------|
| 1 | `f9365a88` | `sessions-unification/pr1-session-lifecycle-api` | `SessionLifecycleAPI` protocol + iOS conformance |
| 2 | `c2073ea6` | `sessions-unification/pr2-ios-cleanup` | iOS Contest intent + grid swap + intent picker graduation + standalone Contests removed (v1.93.0) |
| 3 | `8d5ac8be` | `sessions-unification/pr3-macos-sessions-landing` | macOS Sessions sidebar landing (stubbed) |
| 4 | `ad7a47b9` | `sessions-unification/pr4-macos-session-lifecycle` | macOS `MacSessionManager` + `MacSessionStartSheet` |
| 5 | `72b85d27` | `sessions-unification/pr5-loose-qso-backfill` | `SessionBackfillService` silent per-UTC-day grouping |
| 6 | `90b1bec5` | `sessions-unification/pr6-macos-contest-intent` | macOS Contest intent → `ContestPickerView` → contest session |
| 7 | `951daea8` | `sessions-unification/pr7-macos-contest-chrome` | `ContestSessionContainer` renders contest UI from Sessions sidebar |
| 8 | `690d32bf` | `sessions-unification/pr8-cabrillo-relocation` | `SidebarItem.contests` removed; Cabrillo on Sessions toolbar |
| 9 | `(pending)` | `sessions-unification/pr9-polish-and-release` | Version bumps, `WhatsNewEntry`s, Pre-unification visual treatment, this doc |

## Known follow-ups not in this initiative

- **Contest exchange parser unification** (Q9 polish). `ParsedEntryView` doesn't yet accept an optional `ContestExchange` to drive contest exchanges from the standard quick-entry box. `ContestEntryBar` stays the contest entry surface. Future work: merge the parsers so contests use the same entry component as Casual / POTA.
- **Past-session Cabrillo re-export** (Q14 follow-up). The session-row context menu and the end-session prompt entry points aren't wired yet — `ContestManager` derives Cabrillo from live engine state, not from `session.qsos`. A pure-function `CabrilloExporter(session:definition:)` is the right shape; this PR set keeps the existing `ContestManager.cabrilloText` plumbing.
- **iOS auto-Casual on first QSO** (Q5 commitment). `MacSessionManager.startCasualSession(myCallsign:)` exists for the auto-Casual flow, but `SessionsSidebarRoot` hides `ParsedEntryView` whenever no active session exists, so the codepath isn't reachable from the current landing. PR9-grade polish would either add a quick-log strip to the landing or split the landing dispatch differently.
- **`ContestManager` double-creation audit**. `ContestManager.start()` calls `resumeOrCreateSession` which may create a second `LoggingSession` for the same contest if the row started via `MacSessionManager` doesn't match its resume predicate. In practice the predicate matches `statusRawValue == "active"` + same `contestId`, so duplicates are unusual. A consolidation pass is queued for a follow-up.

## Tests

Backfill (PR5) has unit-test scaffolding in mind but no tests in this PR set (running the iOS suite on `theseus` revealed an unrelated pre-existing `SwiftDataError.loadIssueModelContainer` regression that affects ~230 of 477 tests; investigation separate from CAR-276). Both platforms build cleanly under `xc build` / `xcodebuild`.

## Design context

The 15 design forks resolved during the `/grill-me` session are captured in CAR-276's comment thread on Linear.
