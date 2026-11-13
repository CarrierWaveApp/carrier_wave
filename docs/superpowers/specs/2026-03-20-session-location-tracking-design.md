# Session Location Tracking Design

**Date:** 2026-03-20
**Status:** Draft
**Problem:** Session locations aren't storing properly. GPS location should auto-populate on session start, update as the device moves, and fall back to manual entry when unavailable.

## Current Behavior

- **Logger (activation sessions):** No GPS integration. Grid is manual-entry only in `SessionStartSheet`, defaulting from `@AppStorage("loggerDefaultGrid")`. `LoggingSession.myGrid` is set once at start and never updated. QSOs snapshot `session.myGrid` at log time.
- **Activity Log (hunter sessions):** One-shot GPS via `GridLocationService` when station profile has `useCurrentLocation == true`. Grid changes show a confirmation modal (`LocationChangeSheet`). GPS failures are silent with no UI feedback.

## Expected Behavior

1. Initial session location auto-populates from device GPS
2. As the device moves, QSO locations reflect the current device grid square
3. If GPS is unavailable, the setup wizard prompts for manual entry with a clear message

## Design

### New Service: LocationSessionService

A `@MainActor @Observable` service that wraps `CLLocationManager` for continuous grid tracking.

**Responsibilities:**
- Request location authorization on start
- Run continuous monitoring (`startUpdatingLocation`) at `kCLLocationAccuracyHundredMeters`
- Convert each location fix to a 6-char Maidenhead grid via `MaidenheadConverter`
- Expose `currentGrid: String?` — only publishes when the grid actually changes
- Expose `authorizationStatus` and `lastError: String?` for UI fallback
- `start()` / `stop()` lifecycle tied to session start/end

**Grid boundary debounce:** Require the new grid to be stable for 2 consecutive location fixes before updating, preventing noisy toggling at grid boundaries. At `kCLLocationAccuracyHundredMeters`, fixes typically arrive every 5-15 seconds, so the debounce window is short.

**Single instance:** Both `LoggingSessionManager` and `ActivityLogManager` share a single `LocationSessionService` instance, injected from the app's dependency root. Only one `CLLocationManager` runs at a time. Each manager calls `start()`/`stop()` independently; the service reference-counts and only truly stops when all callers have stopped.

**Location:** `CarrierWave/Services/LocationSessionService.swift`

### Testability Protocol

```swift
protocol LocationProviding: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

extension CLLocationManager: LocationProviding {}
```

Production uses `CLLocationManager`, tests inject a mock that can control `authorizationStatus` and `desiredAccuracy`. `LocationSessionService` holds `any LocationProviding`.

**Location:** `CarrierWave/Protocols/LocationProviding.swift`

### Logger Path (LoggingSessionManager)

**Ownership:** `LoggingSessionManager` gains a `locationService: LocationSessionService` property, created at init.

**Session start:**
1. `startSession()` calls `locationService.start()`
2. If `myGrid` param from the wizard is nil and `locationService.currentGrid` is available, use it
3. As the service publishes grid changes, the manager silently updates `activeSession.myGrid` and sets `cloudDirtyFlag = true`

**Session lifecycle:**
- `endSession()` / `pauseSession()` → `locationService.stop()`
- `resumeSession()` (both no-arg and `resumeSession(_:)` overloads) → `locationService.start()`
- `deleteCurrentSession()` / `deleteSession(_:)` → `locationService.stop()`
- `loadActiveSession()` (app relaunch) → `locationService.start()`

**QSO logging:** No change needed. `logQSO()` already snapshots `session.myGrid` at log time. Continuous updates keep `session.myGrid` current.

**SessionStartSheet changes:**
- On `.task`, auto-request GPS via the manager's `locationService`
- If GPS returns before "Start" is tapped, pre-fill the `myGrid` field
- If GPS fails or permission denied, show inline "Location unavailable — enter grid manually" below the grid field
- User can always override GPS-derived grid by typing

### Activity Log Path (ActivityLogManager)

**Ownership:** `ActivityLogManager` gains the same `locationService: LocationSessionService` property.

**Profile toggle:** `StationProfile.useCurrentLocation` controls whether GPS updates flow through:
- `true` → `locationService.start()` on log activation; grid changes update `activeLog.currentGrid`
- `false` → `locationService.stop()`; grid stays at profile's fixed value

**Lifecycle mapping:**
- `createLog()` / `activateLog()` → if `useCurrentLocation`, call `locationService.start()`
- `deactivateLog()` → `locationService.stop()`
- `switchProfile()` → stop if old profile used location; start if new profile does; revert to fixed grid if stopping

**Setup sheet:** Same GPS pre-fill as SessionStartSheet when `useCurrentLocation == true`.

### Manual Grid Override

If a user manually edits `myGrid` during an active session (e.g., via rove stop or direct edit), GPS updates continue but will overwrite the manual value on the next grid change. This is intentional — if the user is moving, GPS should track. Users who want a fixed grid should use a station profile with `useCurrentLocation == false`.

### Migration Notes

- `@AppStorage("loggerDefaultGrid")` continues to serve as the manual fallback default when GPS is unavailable. Existing user defaults are preserved.
- `GridLocationService` is kept for non-session one-shot use cases (map centering in `AzimuthalStandaloneView`, SDR distance sorting in `WebSDRFavoritesView`, profile grid preview in `AddEditProfileSheet`, rove stop grid pre-fill in `NextRoveStopSheet`). Only session-scoped location tracking moves to `LocationSessionService`.

### Removed Components

- **`LocationChangeSheet`** — no longer needed since updates are silent

### Cloud Sync

Grid changes during a session set `cloudDirtyFlag = true`. The existing sync engine already batches dirty records, so frequent grid changes during mobile operation won't trigger per-change sync cycles. Sync fires on its normal cadence.

### Error Handling

| State | Behavior |
|-------|----------|
| Not determined | `requestWhenInUseAuthorization()` on service start |
| Denied / Restricted | Don't monitor. `currentGrid` stays nil. Views show fallback message. |
| Authorized | Normal continuous monitoring |
| Revoked mid-session | Stop monitoring. `myGrid` keeps last known value. |

### Edge Cases

- **Background/suspend:** `startUpdatingLocation` auto-pauses when backgrounded, resumes on foreground. QSOs are only logged in foreground so no gap.
- **Rove sessions:** `nextRoveStop()` naturally gets current GPS-derived grid from `session.myGrid`. No special changes.
- **Battery:** `kCLLocationAccuracyHundredMeters` uses Wi-Fi/cell triangulation (low power). Grid squares are ~3km so this accuracy is sufficient.

## Files Changed

| File | Change |
|------|--------|
| `CarrierWave/Services/LocationSessionService.swift` | **New** — continuous grid monitoring service |
| `CarrierWave/Protocols/LocationProviding.swift` | **New** — testability protocol for CLLocationManager |
| `CarrierWave/Services/LoggingSessionManager.swift` | Add `locationService` property, start on session start |
| `CarrierWave/Services/LoggingSessionManager+SessionManagement.swift` | Stop/start on pause/resume/end |
| `CarrierWave/Views/Logger/SessionStartSheet.swift` | GPS pre-fill on `.task`, fallback message |
| `CarrierWave/Views/Logger/SessionStartSheet+Sections.swift` | Inline fallback text in grid section |
| `CarrierWave/Services/ActivityLogManager.swift` | Add `locationService`, wire to profile toggle |
| `CarrierWave/Views/ActivityLog/ActivityLogView.swift` | Remove `GridLocationService` usage, remove `LocationChangeSheet` binding |
| `CarrierWave/Views/ActivityLog/ActivityLogSetupSheet.swift` | GPS pre-fill when `useCurrentLocation` |
| `CarrierWave/Views/ActivityLog/LocationChangeSheet.swift` | **Delete** |
| `CarrierWaveTests/` | New tests for `LocationSessionService` with mock provider |
