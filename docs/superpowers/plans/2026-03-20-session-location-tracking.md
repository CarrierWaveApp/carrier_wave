# Session Location Tracking Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add continuous GPS-based grid tracking to both Logger and Activity Log paths, with auto-fill on session start and silent updates as the device moves.

**Architecture:** A shared `LocationSessionService` wraps `CLLocationManager` for continuous monitoring. Both `LoggingSessionManager` and `ActivityLogManager` receive the same instance via injection. The service exposes observable `currentGrid` with debounce; managers subscribe and update their session models.

**Tech Stack:** SwiftUI, CoreLocation, Observation framework, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-20-session-location-tracking-design.md`

---

### Task 1: LocationProviding protocol

**Files:**
- Create: `CarrierWave/Services/LocationProviding.swift`

- [ ] **Step 1: Create the protocol file**

```swift
import CoreLocation

// MARK: - LocationProviding

/// Abstraction over CLLocationManager for testability.
/// Production uses CLLocationManager; tests inject a mock.
protocol LocationProviding: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

// MARK: - CLLocationManager + LocationProviding

extension CLLocationManager: LocationProviding {}
```

- [ ] **Step 2: Run SwiftFormat and SwiftLint**

Run: `swiftformat CarrierWave/Services/LocationProviding.swift && swiftlint lint --path CarrierWave/Services/LocationProviding.swift`
Expected: No violations

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Services/LocationProviding.swift
git commit -m "feat: add LocationProviding protocol for testable location services"
```

---

### Task 2: LocationSessionService

**Files:**
- Create: `CarrierWave/Services/LocationSessionService.swift`

- [ ] **Step 1: Create the service**

```swift
import CarrierWaveCore
import CoreLocation
import Observation

// MARK: - LocationSessionService

/// Continuous GPS → Maidenhead grid tracking for logging sessions.
/// Shared between LoggingSessionManager and ActivityLogManager.
/// Uses reference-counted start/stop so multiple callers can
/// independently request monitoring.
@MainActor
@Observable
final class LocationSessionService: NSObject {
    // MARK: Lifecycle

    init(locationProvider: any LocationProviding = CLLocationManager()) {
        self.locationProvider = locationProvider
        super.init()
        locationProvider.delegate = self
        locationProvider.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: Internal

    /// The current GPS-derived 6-character grid square, or nil if unknown.
    /// Only updates when the grid actually changes (with debounce).
    private(set) var currentGrid: String?

    /// Current authorization status for UI fallback display
    private(set) var locationAuthorized: Bool = false

    /// Whether a location error occurred (for UI fallback message)
    private(set) var locationError: String?

    /// Whether the service is actively monitoring
    var isMonitoring: Bool { startCount > 0 }

    /// Request monitoring start. Reference-counted — call `stop()` once
    /// for each `start()` call.
    func start() {
        startCount += 1
        guard startCount == 1 else {
            return
        }
        locationError = nil
        let status = locationProvider.authorizationStatus
        locationAuthorized = status == .authorizedWhenInUse
            || status == .authorizedAlways
        if status == .notDetermined {
            locationProvider.requestWhenInUseAuthorization()
        } else if locationAuthorized {
            locationProvider.startUpdatingLocation()
        } else {
            locationError = "Location permission denied"
        }
    }

    /// Decrement the reference count. Stops monitoring when it reaches zero.
    func stop() {
        guard startCount > 0 else {
            return
        }
        startCount -= 1
        guard startCount == 0 else {
            return
        }
        locationProvider.stopUpdatingLocation()
        pendingGrid = nil
        pendingGridCount = 0
    }

    /// Force-stop regardless of reference count (for cleanup)
    func forceStop() {
        startCount = 0
        locationProvider.stopUpdatingLocation()
        pendingGrid = nil
        pendingGridCount = 0
    }

    // MARK: Private

    private let locationProvider: any LocationProviding
    private var startCount = 0

    /// Debounce: require 2 consecutive fixes with the same new grid
    private var pendingGrid: String?
    private var pendingGridCount = 0
}

// MARK: CLLocationManagerDelegate

extension LocationSessionService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            return
        }
        let grid = MaidenheadConverter.grid(from: location.coordinate)
        Task { @MainActor in
            self.processGridUpdate(grid)
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.locationError = message
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _: CLLocationManager
    ) {
        // Read status from our own provider, not the passed manager parameter,
        // so tests can control authorization via the mock.
        Task { @MainActor in
            let status = self.locationProvider.authorizationStatus
            let authorized = status == .authorizedWhenInUse
                || status == .authorizedAlways
            self.locationAuthorized = authorized
            if authorized, self.isMonitoring {
                self.locationError = nil
                self.locationProvider.startUpdatingLocation()
            } else if !authorized, self.isMonitoring {
                self.locationError = "Location permission denied"
                self.locationProvider.stopUpdatingLocation()
            }
        }
    }

    // MARK: Private helpers

    @MainActor
    private func processGridUpdate(_ grid: String) {
        // Same as current — no update needed
        guard grid != currentGrid else {
            pendingGrid = nil
            pendingGridCount = 0
            return
        }

        // Debounce: require 2 consecutive fixes at the new grid
        if grid == pendingGrid {
            pendingGridCount += 1
        } else {
            pendingGrid = grid
            pendingGridCount = 1
        }

        if pendingGridCount >= 2 {
            currentGrid = grid
            pendingGrid = nil
            pendingGridCount = 0
        }
    }
}
```

- [ ] **Step 2: Run SwiftFormat and SwiftLint**

Run: `swiftformat CarrierWave/Services/LocationSessionService.swift && swiftlint lint --path CarrierWave/Services/LocationSessionService.swift`
Expected: No violations

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Services/LocationSessionService.swift
git commit -m "feat: add LocationSessionService for continuous grid tracking"
```

---

### Task 3: Tests for LocationSessionService

**Files:**
- Create: `CarrierWaveTests/LocationSessionServiceTests.swift`

- [ ] **Step 1: Create mock and tests**

```swift
import CoreLocation
import Testing

@testable import CarrierWave

// MARK: - MockLocationProvider

@MainActor
final class MockLocationProvider: LocationProviding {
    var delegate: (any CLLocationManagerDelegate)?
    var desiredAccuracy: CLLocationAccuracy = 0
    var mockAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    var authorizationStatus: CLAuthorizationStatus { mockAuthorizationStatus }

    private(set) var startUpdatesCalled = 0
    private(set) var stopUpdatesCalled = 0
    private(set) var authRequested = false

    func requestWhenInUseAuthorization() {
        authRequested = true
    }

    func startUpdatingLocation() {
        startUpdatesCalled += 1
    }

    func stopUpdatingLocation() {
        stopUpdatesCalled += 1
    }

    /// Simulate a location fix
    func simulateLocation(latitude: Double, longitude: Double) {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        delegate?.locationManager?(
            CLLocationManager(),
            didUpdateLocations: [location]
        )
    }

    /// Simulate an error
    func simulateError(_ error: Error) {
        delegate?.locationManager?(
            CLLocationManager(),
            didFailWithError: error
        )
    }

    /// Simulate authorization change
    func simulateAuthorizationChange(_ status: CLAuthorizationStatus) {
        mockAuthorizationStatus = status
        // Create a temporary CLLocationManager to pass to the delegate
        // The service reads status from its own provider, not the passed manager
        let tempManager = CLLocationManager()
        delegate?.locationManagerDidChangeAuthorization?(tempManager)
    }
}

// MARK: - LocationSessionServiceTests

@Suite("LocationSessionService")
struct LocationSessionServiceTests {
    @MainActor
    @Test("start requests authorization when not determined")
    func startRequestsAuth() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .notDetermined
        let service = LocationSessionService(locationProvider: mock)

        service.start()

        #expect(mock.authRequested)
        #expect(mock.startUpdatesCalled == 0)
        #expect(service.isMonitoring)
    }

    @MainActor
    @Test("start begins monitoring when authorized")
    func startBeginsMonitoring() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)

        service.start()

        #expect(mock.startUpdatesCalled == 1)
        #expect(service.isMonitoring)
        #expect(service.locationAuthorized)
    }

    @MainActor
    @Test("start sets error when denied")
    func startSetsErrorWhenDenied() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .denied
        let service = LocationSessionService(locationProvider: mock)

        service.start()

        #expect(service.locationError != nil)
        #expect(mock.startUpdatesCalled == 0)
    }

    @MainActor
    @Test("stop decrements reference count")
    func stopDecrementsRefCount() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)

        service.start()
        service.start()
        service.stop()

        #expect(service.isMonitoring)
        #expect(mock.stopUpdatesCalled == 0)

        service.stop()

        #expect(!service.isMonitoring)
        #expect(mock.stopUpdatesCalled == 1)
    }

    @MainActor
    @Test("grid updates after 2 consecutive fixes at same grid")
    func gridDebounce() async {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)
        service.start()

        // FN31 center is approx 41.0, -74.0
        mock.simulateLocation(latitude: 41.0, longitude: -74.0)
        // Need to yield for the Task { @MainActor } to execute
        await Task.yield()
        #expect(service.currentGrid == nil) // First fix, not yet confirmed

        mock.simulateLocation(latitude: 41.0, longitude: -74.0)
        await Task.yield()
        #expect(service.currentGrid != nil) // Second fix confirms
    }

    @MainActor
    @Test("grid does not update on alternating fixes")
    func gridNoUpdateOnAlternating() async {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)
        service.start()

        // Two different grids alternating
        mock.simulateLocation(latitude: 41.0, longitude: -74.0)
        await Task.yield()
        mock.simulateLocation(latitude: 35.0, longitude: -80.0)
        await Task.yield()
        mock.simulateLocation(latitude: 41.0, longitude: -74.0)
        await Task.yield()

        #expect(service.currentGrid == nil) // No 2 consecutive matches
    }

    @MainActor
    @Test("forceStop resets reference count")
    func forceStopResetsCount() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)

        service.start()
        service.start()
        service.forceStop()

        #expect(!service.isMonitoring)
        #expect(mock.stopUpdatesCalled == 1)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `xc test-unit` (or verify tests compile if in cloud environment)
Expected: All LocationSessionServiceTests pass

- [ ] **Step 3: Commit**

```bash
git add CarrierWaveTests/LocationSessionServiceTests.swift
git commit -m "test: add LocationSessionService unit tests with mock provider"
```

---

### Task 4: Integrate LocationSessionService into LoggingSessionManager

**Files:**
- Modify: `CarrierWave/Services/LoggingSessionManager.swift`
- Modify: `CarrierWave/Services/LoggingSessionManager+SessionManagement.swift`

- [ ] **Step 1: Add locationService property and observation to LoggingSessionManager.swift**

In `LoggingSessionManager.swift`, add property after line 37 (`let liveActivityService = LiveActivityService()`):

```swift
/// Shared location service for continuous grid tracking
let locationService: LocationSessionService
```

Update `init` to accept and store the service:

```swift
init(modelContext: ModelContext, locationService: LocationSessionService = LocationSessionService()) {
    self.modelContext = modelContext
    self.locationService = locationService
    loadActiveSession()
}
```

In `startSession()`, after `activateSession(session, autoStartSDR: autoStartSDR)` (line 159), add:

```swift
locationService.start()
```

Also in `startSession()`, change the `myGrid` assignment on the `LoggingSession` init (line 128). After the session is created (after line 141), add GPS fallback:

```swift
// If no grid was provided but GPS has a fix, use it
if session.myGrid == nil, let gpsGrid = locationService.currentGrid {
    session.myGrid = gpsGrid
}
```

In `activateSession()`, at the end (before `try? modelContext.save()` on line 263), set up grid observation. Since `@Observable` properties are observed via `withObservationTracking`, add a method that watches for grid changes:

```swift
startGridObservation()
```

Add the grid observation method at the bottom of the file (private section):

```swift
/// Observe location service grid changes and update the active session
private func startGridObservation() {
    observeGridChanges()
}

private func observeGridChanges() {
    withObservationTracking {
        _ = self.locationService.currentGrid
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self, let session = self.activeSession else {
                return
            }
            if let newGrid = self.locationService.currentGrid,
               newGrid != session.myGrid
            {
                session.myGrid = newGrid
                session.cloudDirtyFlag = true
                try? self.modelContext.save()
            }
            // Re-register for the next change
            self.observeGridChanges()
        }
    }
}
```

- [ ] **Step 2: Add location stop/start to session lifecycle methods in LoggingSessionManager+SessionManagement.swift**

In `endSession()`, add after `endLiveActivity()` (line 15):
```swift
locationService.stop()
```

In `pauseSession()`, add after `pauseLiveActivity()` (line 94):
```swift
locationService.stop()
```

In `resumeSession()` (no-arg, line 132), add after `session.resume()` (line 136):
```swift
locationService.start()
startGridObservation()
```

In `resumeSession(_ session:)` (line 165), add after `startLiveActivity()` (line 174):
```swift
locationService.start()
startGridObservation()
```

In `deleteCurrentSession()` (line 198), add after `endLiveActivity()` (line 203):
```swift
locationService.stop()
```

In `deleteSession(_:)` (line 330), add at the top of the `if session.id == activeSession?.id` branch (line 332), before `endSession()`:
The `endSession()` call already handles `locationService.stop()`, so no change needed here. But for the `else` branch where the session is not the active one, no location stop is needed (it's not being tracked).

- [ ] **Step 3: Update loadActiveSession to start location service**

In `loadActiveSession()` in `LoggingSessionManager.swift`, inside the `if let session = sessions.first, session.isActive` block (after line 309 `connectBLERadio()`), add:
```swift
locationService.start()
startGridObservation()
```

- [ ] **Step 4: Make startGridObservation and observeGridChanges accessible from extension**

Since `LoggingSessionManager+SessionManagement.swift` is an extension, `startGridObservation()` and `observeGridChanges()` must be `internal` (not `private`). Declare them without access modifier in the main file.

- [ ] **Step 5: Run SwiftFormat and SwiftLint on both files**

Run: `swiftformat CarrierWave/Services/LoggingSessionManager.swift CarrierWave/Services/LoggingSessionManager+SessionManagement.swift && swiftlint lint --path CarrierWave/Services/LoggingSessionManager.swift --path CarrierWave/Services/LoggingSessionManager+SessionManagement.swift`
Expected: No violations

- [ ] **Step 6: Commit**

```bash
git add CarrierWave/Services/LoggingSessionManager.swift CarrierWave/Services/LoggingSessionManager+SessionManagement.swift
git commit -m "feat: integrate LocationSessionService into LoggingSessionManager"
```

---

### Task 5: Share a single LocationSessionService via SwiftUI Environment

**Files:**
- Create: `CarrierWave/Services/LocationSessionService+Environment.swift`
- Modify: `CarrierWave/Views/Dashboard/DashboardView.swift`
- Modify: `CarrierWave/Views/Logger/LoggerView+Modifiers.swift`
- Modify: `CarrierWave/Views/Sessions/SessionsTabView.swift`

`LoggingSessionManager` and `ActivityLogManager` are created in different view hierarchies (`SessionsTabView`/`LoggerView+Modifiers` vs `DashboardView`). To share one `LocationSessionService`, use a SwiftUI `@Environment` value set at the app root.

- [ ] **Step 1: Create the Environment key**

Create `CarrierWave/Services/LocationSessionService+Environment.swift`:
```swift
import SwiftUI

// MARK: - LocationSessionServiceKey

private struct LocationSessionServiceKey: EnvironmentKey {
    @MainActor
    static let defaultValue = LocationSessionService()
}

extension EnvironmentValues {
    var locationSessionService: LocationSessionService {
        get { self[LocationSessionServiceKey.self] }
        set { self[LocationSessionServiceKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Inject the shared instance at the app root**

Find the app's root `@main` struct or scene builder. Add:
```swift
@State private var locationService = LocationSessionService()
```

And on the root view:
```swift
.environment(\.locationSessionService, locationService)
```

- [ ] **Step 3: Update DashboardView to read from environment**

In `DashboardView.swift`, add:
```swift
@Environment(\.locationSessionService) private var locationService
```

Pass it when creating managers:
```swift
ActivityLogManager(modelContext: modelContext, locationService: locationService)
```

- [ ] **Step 4: Update SessionsTabView and LoggerView+Modifiers**

In each file, add `@Environment(\.locationSessionService) private var locationService` and pass it to `LoggingSessionManager(modelContext:locationService:)`.

`LoggingSessionManager+SessionActivity.swift:151` creates a temporary manager for background work — the default init (its own `LocationSessionService`) is fine here since it doesn't need GPS tracking.

- [ ] **Step 5: Run SwiftFormat and SwiftLint on all changed files**

- [ ] **Step 6: Commit**

```bash
git add CarrierWave/Services/LocationSessionService+Environment.swift \
    CarrierWave/Views/Dashboard/DashboardView.swift \
    CarrierWave/Views/Logger/LoggerView+Modifiers.swift \
    CarrierWave/Views/Sessions/SessionsTabView.swift
git commit -m "feat: share LocationSessionService via SwiftUI Environment"
```

---

### Task 6: Integrate LocationSessionService into ActivityLogManager

**Files:**
- Modify: `CarrierWave/Services/ActivityLogManager.swift`

- [ ] **Step 1: Add locationService property and update init**

Add property after `let modelContext: ModelContext` (line 44):
```swift
/// Shared location service for continuous grid tracking
let locationService: LocationSessionService
```

Update init:
```swift
init(modelContext: ModelContext, locationService: LocationSessionService = LocationSessionService()) {
    self.modelContext = modelContext
    self.locationService = locationService
    loadActiveLog()
    refreshCurrentProfile()
}
```

- [ ] **Step 2: Start/stop location in lifecycle methods**

In `createLog()` (line 79), after `refreshTodayStats()` (line 105), add:
```swift
if currentProfile?.useCurrentLocation == true {
    locationService.start()
    startGridObservation()
}
```

In `activateLog(_ log:)` (line 109), after `refreshTodayStats()` (line 122), add:
```swift
if currentProfile?.useCurrentLocation == true {
    locationService.start()
    startGridObservation()
}
```

In `deactivateLog()` (line 126), after `clearActiveLogId()` (line 133), add:
```swift
locationService.stop()
```

In `deleteLog(_ log:)` (line 138), inside the `if activeLog?.id == log.id` block (line 139), add before clearing `activeLog`:
```swift
locationService.stop()
```

In `switchProfile(_ profile:)` (line 148), replace the body with:
```swift
func switchProfile(_ profile: StationProfile) {
    guard let log = activeLog else {
        return
    }

    // Stop location if old profile used it
    if currentProfile?.useCurrentLocation == true {
        locationService.stop()
    }

    log.stationProfileId = profile.id
    if !profile.useCurrentLocation, let grid = profile.grid {
        log.currentGrid = grid
    }
    log.cloudDirtyFlag = true
    try? modelContext.save()
    refreshCurrentProfile()

    // Start location if new profile uses it
    if profile.useCurrentLocation {
        locationService.start()
        startGridObservation()
    }
}
```

- [ ] **Step 3: Add grid observation methods**

Add to the `ActivityLogManager` class body:
```swift
/// Observe location service grid changes and update the active log
func startGridObservation() {
    observeGridChanges()
}

private func observeGridChanges() {
    withObservationTracking {
        _ = self.locationService.currentGrid
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self, let log = self.activeLog else {
                return
            }
            if let newGrid = self.locationService.currentGrid,
               newGrid != log.currentGrid
            {
                log.currentGrid = newGrid
                log.cloudDirtyFlag = true
                try? self.modelContext.save()
            }
            self.observeGridChanges()
        }
    }
}
```

- [ ] **Step 4: Start location on loadActiveLog if profile uses current location**

In the private `loadActiveLog()` method, inside the `if let log = logs.first, log.isActive` block (line 410), after setting `activeLog = log`, add:
```swift
// Defer location start to after refreshCurrentProfile runs in init
// (currentProfile isn't set yet during init). The caller should
// check and start location after init completes.
```

Actually, since `loadActiveLog()` runs before `refreshCurrentProfile()` in init, we can't check the profile here. Instead, add a post-init location check. After `refreshCurrentProfile()` in init, add:
```swift
// Start location tracking if active profile uses current location
if activeLog != nil, currentProfile?.useCurrentLocation == true {
    locationService.start()
    startGridObservation()
}
```

- [ ] **Step 5: Run SwiftFormat and SwiftLint**

Run: `swiftformat CarrierWave/Services/ActivityLogManager.swift && swiftlint lint --path CarrierWave/Services/ActivityLogManager.swift`
Expected: No violations

- [ ] **Step 6: Commit**

```bash
git add CarrierWave/Services/ActivityLogManager.swift
git commit -m "feat: integrate LocationSessionService into ActivityLogManager"
```

---

### Task 7: GPS pre-fill in SessionStartSheet

**Files:**
- Modify: `CarrierWave/Views/Logger/SessionStartSheet.swift`
- Modify: `CarrierWave/Views/Logger/SessionStartSheet+Sections.swift`

The sheet accesses location via `sessionManager?.locationService` (no new property needed). On appearance, if no grid is set, it starts a temporary location request and cleans up on dismiss.

- [ ] **Step 1: Add GPS pre-fill state and logic to SessionStartSheet.swift**

Add a `@State` property in the private section (after line 270):
```swift
@State private var startedLocationForPreFill = false
```

In the `.task` modifier (line 132), after the existing defaults loading (after line 159 `loadSavedPrograms()` block), add:
```swift
// Auto-fill grid from GPS if no default
if myGrid.isEmpty, defaultGrid.isEmpty {
    if let gpsGrid = sessionManager?.locationService.currentGrid {
        myGrid = gpsGrid
    } else {
        sessionManager?.locationService.start()
        startedLocationForPreFill = true
    }
}
```

Add an `.onDisappear` modifier after the `.task` block:
```swift
.onDisappear {
    if startedLocationForPreFill {
        sessionManager?.locationService.stop()
    }
}
```

Add an `.onChange` modifier to pick up late GPS results:
```swift
.onChange(of: sessionManager?.locationService.currentGrid) { _, newGrid in
    if let newGrid, myGrid.isEmpty {
        myGrid = newGrid
    }
}
```

- [ ] **Step 2: Update gridRow in SessionStartSheet+Sections.swift**

The `gridRow` currently only shows when `!defaultGrid.isEmpty || !myGrid.isEmpty` (line 89). Change it to always show, with status indicators:

```swift
@ViewBuilder
var gridRow: some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text("Grid")
                .foregroundStyle(.secondary)
            Spacer()
            TextField("FN31", text: $myGrid)
                .textInputAutocapitalization(.characters)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospaced())
        }
        if myGrid.isEmpty,
           sessionManager?.locationService.locationError != nil
        {
            Text("Location unavailable — enter grid manually")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if myGrid.isEmpty,
                  sessionManager?.locationService.isMonitoring == true
        {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Getting location...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 3: Run SwiftFormat and SwiftLint**

- [ ] **Step 4: Commit**

```bash
git add CarrierWave/Views/Logger/SessionStartSheet.swift CarrierWave/Views/Logger/SessionStartSheet+Sections.swift
git commit -m "feat: GPS pre-fill and fallback message in SessionStartSheet"
```

---

### Task 8: Remove LocationChangeSheet from ActivityLogView

**Files:**
- Modify: `CarrierWave/Views/ActivityLog/ActivityLogView.swift`
- Delete: `CarrierWave/Views/ActivityLog/LocationChangeSheet.swift`

- [ ] **Step 1: Remove LocationChangeSheet usage from ActivityLogView**

Remove the `.sheet(isPresented: $showingLocationChange)` block (lines 76-97).

Remove these `@State` properties:
- `showingLocationChange` (line 212)
- `detectedGrid` (line 215)
- `locationService` (line 226) — the `GridLocationService` instance

Remove the `.onChange(of: locationService.currentGrid)` block (lines 172-178). The grid is now updated by `ActivityLogManager` via its own observation of `LocationSessionService`.

Remove the `requestGPSGridIfNeeded()` function (lines 434-438).

Remove the call to `requestGPSGridIfNeeded()` in `.task` (line 157).

Remove the call to `requestGPSGridIfNeeded()` in the profile picker sheet's `set` closure (line 61).

Remove the `import CoreLocation` if it was only used for `LocationChangeSheet`.

- [ ] **Step 2: Delete LocationChangeSheet.swift**

```bash
git rm CarrierWave/Views/ActivityLog/LocationChangeSheet.swift
```

- [ ] **Step 3: Run SwiftFormat and SwiftLint**

Run: `swiftformat CarrierWave/Views/ActivityLog/ActivityLogView.swift && swiftlint lint --path CarrierWave/Views/ActivityLog/ActivityLogView.swift`
Expected: No violations

- [ ] **Step 4: Commit**

```bash
git add CarrierWave/Views/ActivityLog/ActivityLogView.swift
git rm CarrierWave/Views/ActivityLog/LocationChangeSheet.swift
git commit -m "feat: remove LocationChangeSheet, grid updates now silent via LocationSessionService"
```

---

### Task 9: Migrate ActivityLogSetupSheet from GridLocationService to LocationSessionService

**Files:**
- Modify: `CarrierWave/Views/ActivityLog/ActivityLogSetupSheet.swift`

The setup sheet currently uses its own `GridLocationService` instance (line 162) for one-shot GPS when `useCurrentLocation` is toggled. Migrate to the shared `LocationSessionService` via the manager.

- [ ] **Step 1: Replace GridLocationService with manager's LocationSessionService**

Replace the `@State private var locationService = GridLocationService()` (line 162) with:
```swift
// Location service accessed via manager?.locationService
```
(Just remove the property — the manager now owns location.)

Update the `useCurrentLocation` `.onChange` handler (line 118-122). Replace:
```swift
.onChange(of: useCurrentLocation) { _, isOn in
    if isOn {
        locationService.requestGrid()
    }
}
```
With:
```swift
.onChange(of: useCurrentLocation) { _, isOn in
    if isOn {
        manager?.locationService.start()
    } else {
        manager?.locationService.stop()
    }
}
```

Add cleanup on dismiss — in the Cancel button (line 111) and after `createLog()` (line 231), stop if we started:
```swift
.onDisappear {
    if useCurrentLocation {
        manager?.locationService.stop()
    }
}
```

Update the GPS status display (lines 84-93). Replace `locationService.isLocating` with `manager?.locationService.isMonitoring == true` and `locationService.currentGrid` with `manager?.locationService.currentGrid`:

```swift
if useCurrentLocation {
    HStack {
        Label {
            if manager?.locationService.isMonitoring == true,
               manager?.locationService.currentGrid == nil
            {
                Text("Locating...")
                    .foregroundStyle(.secondary)
            } else if let gpsGrid = manager?.locationService.currentGrid {
                Text(gpsGrid)
                    .font(.body.monospaced())
            } else if manager?.locationService.locationError != nil {
                Text("Location unavailable")
                    .foregroundStyle(.orange)
            } else {
                Text("Waiting for GPS")
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "location.fill")
                .foregroundStyle(.blue)
        }
    }
}
```

- [ ] **Step 2: Run SwiftFormat and SwiftLint**

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Views/ActivityLog/ActivityLogSetupSheet.swift
git commit -m "feat: migrate ActivityLogSetupSheet to shared LocationSessionService"
```

---

### Task 10: Update FILE_INDEX.md and CHANGELOG.md

**Files:**
- Modify: `docs/FILE_INDEX.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update FILE_INDEX.md**

Add entries for new files:
- `LocationProviding.swift` — Protocol abstracting CLLocationManager for testability
- `LocationSessionService.swift` — Continuous GPS → Maidenhead grid tracking service
- `LocationSessionService+Environment.swift` — SwiftUI Environment key for shared location service
- `LocationSessionServiceTests.swift` — Unit tests for LocationSessionService

Remove entry for:
- `LocationChangeSheet.swift`

- [ ] **Step 2: Update CHANGELOG.md**

Under `[Unreleased]`, add:

```markdown
### Added
- Continuous GPS-based grid tracking during logging sessions (Logger and Activity Log)
- Auto-fill grid square from GPS when starting a session
- Inline fallback message when GPS is unavailable in session setup

### Changed
- Activity Log grid updates are now silent (no confirmation sheet)
- Both Logger and Activity Log share a single location service instance

### Removed
- LocationChangeSheet (grid change confirmation modal)
```

- [ ] **Step 3: Commit**

```bash
git add docs/FILE_INDEX.md CHANGELOG.md
git commit -m "docs: update file index and changelog for session location tracking"
```
