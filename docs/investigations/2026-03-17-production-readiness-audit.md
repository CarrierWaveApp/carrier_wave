# Investigation: Production Readiness Audit — Carrier Wave Ecosystem

**Date:** 2026-03-17
**Status:** Complete
**Outcome:** 25 findings across iOS app, Rust server, Hetzner infrastructure, and CI/CD pipeline. No data-loss events yet, but critical gaps exist in backups, testing in CI, and concurrency safety.

## Problem Statement

Proactive production readiness assessment of the entire Carrier Wave ecosystem:
- **Carrier Wave iOS app** — SwiftUI/SwiftData amateur radio logger
- **activities-server** — Rust/Axum backend at `~/projects/activities-server`
- **Hetzner infrastructure** — VPS deployment at `~/projects/hetzner`
- **CI/CD pipeline** — GitHub Actions + Xcode Cloud

Goal: identify gaps in performance, deployability, introspectability, security, resilience, and testing before they become production incidents.

## Methodology

9 specialized audit agents ran in parallel:

| Agent | Scope | Duration | Issues Found |
|-------|-------|----------|-------------|
| SwiftUI Performance | iOS app views | ~12 min | 23 |
| Swift Performance | iOS app runtime | ~13 min | 16 |
| Memory Leak | iOS app lifecycle | ~13 min | 3 |
| Concurrency Safety | iOS app Swift 6 | ~17 min | 13 |
| Security & Privacy | iOS app + config | ~7 min | 8 |
| Test Quality | iOS app tests | ~10 min | 7 |
| Energy Efficiency | iOS app battery | ~13 min | 20 |
| Server + Infra | Rust server + Hetzner | ~15 min | 10 critical risks |
| CI/CD Pipeline | GitHub Actions + Xcode Cloud | ~8 min | 5 critical gaps |

Issues were deduplicated and organized into 4 priority tiers.

---

# Findings

## Tier 1 — Data Loss & Outage Risks

### T1-1: No database backup for user data

**Severity:** CRITICAL
**Component:** Hetzner infrastructure / activities-server
**Files:** `~/projects/hetzner/` (no postgres backup role exists)

The Postgres database on the Hetzner VPS has no `pg_dump` cron job, no WAL archiving, no disk snapshots, and no off-site backup. The snapshot system in `activities-server/src/snapshots.rs` only covers aggregated POTA/park/trail data that can be re-fetched from upstream APIs.

**What's at risk:** All user data — challenges, clubs, friendships, events, progress — is on a single VPS disk with no recovery path.

**Recommended fix:** Set up a daily `pg_dump` cron job writing to an off-site location (Hetzner Storage Box, S3, or similar). Add a WAL archiving setup for point-in-time recovery. Document the restore procedure.

---

### T1-2: Tests run nowhere in CI

**Severity:** CRITICAL
**Component:** CI/CD pipeline
**Files:**
- `.github/workflows/ci.yml` — lint-only (Ubuntu, no Xcode)
- `ci_scripts/ci_post_clone.sh` — installs SwiftLint only, no SwiftFormat
- Xcode Cloud — archive-only on `main`, no PR workflow

Neither GitHub Actions nor Xcode Cloud runs any tests. The custom performance audit (preventing banned `@Query` patterns that cause multi-second freezes) runs only in an optional local pre-commit hook requiring manual `make setup-hooks`.

**What runs where:**

| Check | Local Hook | GitHub Actions | Xcode Cloud |
|-------|-----------|---------------|-------------|
| SwiftFormat | Yes (if installed) | Yes | No |
| SwiftLint | Yes (if installed) | Yes | No |
| Performance audit | Yes | **No** | **No** |
| Compilation | No | **No** | Yes (main only) |
| Unit tests | **No** | **No** | **No** |
| UI tests | **No** | **No** | **No** |

**Why this matters:** A broken test suite goes undetected until a developer manually runs tests. A contributor without the pre-commit hook installed can merge performance-destroying `@Query` code undetected. Xcode Cloud only triggers on `main`, so a merge that fails to compile blocks the entire pipeline after the broken code is already on the default branch.

**Recommended fix:**
1. Add Xcode Cloud workflow triggered on PRs to `main` with a test action
2. Port the performance audit script into the GitHub Actions CI job
3. Add a macOS runner job for `swift test` on CarrierWaveCore (no iOS deps, can build on macOS)

---

### T1-3: `nonisolated(unsafe) var` data races on actor caches

**Severity:** CRITICAL
**Component:** iOS app concurrency
**Files:**
- `CarrierWave/Services/POTAParksCache.swift:66,70`
- `CarrierWave/Services/SOTASummitsCache.swift:25,27`
- `CarrierWave/Services/WWFFReferencesCache.swift:25,27`
- `CarrierWave/Services/CallsignNotesCache.swift:203`

These actors use `nonisolated(unsafe) var` on mutable dictionaries to provide synchronous read access via `nonisolated func`. The `nonisolated(unsafe)` annotation completely bypasses actor isolation. Any concurrent read while `ensureLoaded()` writes is an unguarded data race — the compiler cannot verify the "writes complete before reads" contract.

```swift
actor POTAParksCache {
    nonisolated(unsafe) var parks: [String: POTAPark] = [:]           // DATA RACE
    nonisolated(unsafe) var sortedNameIndex: [(word: String, refs: [String])] = []  // DATA RACE
}
```

**What's at risk:** Torn dictionary reads → crashes under concurrent access. Also a Swift 6 strict concurrency blocker.

**Recommended fix:** Replace with `NSLock`-protected snapshots or `Mutex` (iOS 18+):

```swift
private let parksLock = NSLock()
private var _parksSnapshot: [String: POTAPark] = [:]

nonisolated func nameSync(for reference: String) -> String? {
    parksLock.withLock { _parksSnapshot[reference.uppercased()]?.name }
}
```

---

### T1-4: `Cargo.lock` is gitignored in activities-server

**Severity:** CRITICAL
**Component:** Server
**Files:** `~/projects/activities-server/.gitignore:3`

For a binary crate, the lock file MUST be committed. Without it, CI builds may use different dependency versions than local development. Builds are not reproducible.

**Recommended fix:** Remove `Cargo.lock` from `.gitignore` and commit the current lock file.

---

### T1-5: No graceful shutdown on server

**Severity:** CRITICAL
**Component:** Server
**Files:**
- `~/projects/activities-server/src/main.rs:129-130`
- `~/projects/hetzner/roles/activities_server/files/activities-server.service`

`axum::serve(listener, app).await.unwrap()` has no signal handler. SIGTERM from `systemctl stop` kills in-flight requests and background tasks (aggregators, RBN ingester, snapshot loop) mid-operation. The systemd unit has no `RestartSec` delay, no `StartLimitBurst`, no `MemoryMax`, and no `User=` directive (likely runs as root).

**Recommended fix:**
1. Add `with_graceful_shutdown(shutdown_signal())` to the axum serve call
2. Add `User=activities-server`, `RestartSec=5`, `StartLimitBurst=5`, `MemoryMax=512M` to the systemd unit
3. Wire a `tokio::signal::ctrl_c()` handler that drains connections and stops background tasks

---

## Tier 2 — Security & Correctness

### T2-1: ATS `NSAllowsArbitraryLoads = true`

**Severity:** HIGH
**Component:** iOS app security
**Files:** `CarrierWave/Info.plist:20-22`

The entire app can make cleartext HTTP connections. Only 3 endpoints actually need HTTP:

| Endpoint | Reason |
|----------|--------|
| `http://kiwisdr.com/.public/` | Public SDR directory, no auth |
| `http://www.supercheckpartial.com/MASTER.SCP` | Public callsign database |
| `http://host:3000` (CW-SWL) | User's local network server |

All sensitive APIs (QRZ, POTA, LoTW, eQSL, Activities) already use HTTPS.

**What's at risk:** App Store rejection, MITM on non-HTTPS traffic, loss of iOS HTTP/2 connection caching optimizations.

**Recommended fix:** Replace with domain-specific ATS exceptions:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>kiwisdr.com</key>
        <dict>
            <key>NSIncludesSubdomains</key><true/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
        </dict>
        <key>www.supercheckpartial.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
        </dict>
    </dict>
</dict>
```

---

### T2-2: Keychain accessibility too permissive

**Severity:** HIGH
**Component:** iOS app security
**Files:**
- `CarrierWaveData/Sources/CarrierWaveData/Utilities/KeychainHelper.swift:27-42,154`
- `CarrierWave/Utilities/KeychainHelper+Migration.swift:65`

Two issues:
1. Primary `save()` method has **no** `kSecAttrAccessible` attribute — defaults to an unspecified Apple-managed default
2. Shared group uses `kSecAttrAccessibleAfterFirstUnlock` — allows credential access after boot without active unlock

**Recommended fix:** Add `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` to both the primary `save()` and shared group `saveToSharedGroup()` methods.

---

### T2-3: No rate limiting on server API

**Severity:** HIGH
**Component:** Server
**Files:** `~/projects/activities-server/src/main.rs` (router setup)

No rate limiting middleware exists. `POST /v1/register` creates users with no throttle. CORS is `allow_origin(Any)`, `allow_methods(Any)`, `allow_headers(Any)`.

**Recommended fix:** Add `tower::limit::RateLimitLayer` or `tower_governor` for per-IP rate limiting. Restrict CORS to the actual app domains.

---

### T2-4: Admin token comparison is not constant-time

**Severity:** HIGH
**Component:** Server
**Files:** `~/projects/activities-server/src/auth/middleware.rs:98`

`token != admin_token` uses `PartialEq` for `String`, which is not constant-time. Vulnerable to timing attacks.

**Recommended fix:** Use `subtle::ConstantTimeEq` or equivalent constant-time comparison crate.

---

### T2-5: ntfy monitoring password committed in plaintext

**Severity:** HIGH
**Component:** Hetzner infrastructure
**Files:** `~/projects/hetzner/roles/monitoring/defaults/main.yml:6`

```yaml
monitoring_ntfy_pass: "bd2195fdabacd895d735d11de8e33d4920a4f63e"
```

The CLAUDE.md requires vault-encrypted secrets in `*vault*.yml`, but this file is NOT vaulted.

**Recommended fix:** Move to a vault-encrypted vars file and rotate the credential.

---

### T2-6: Debug print statements expose keychain migration details

**Severity:** HIGH
**Component:** iOS app security
**Files:** `CarrierWave/Utilities/KeychainHelper+Migration.swift:39,70`

```swift
print("[Keychain] shared group migration: \(migrated) migrated, \(failed) failed")
print("[Keychain] shared group write failed for \(key): \(status)")
```

Exposes credential key names and keychain status codes in device logs.

**Recommended fix:** Replace with `os.Logger` using privacy levels, or wrap in `#if DEBUG`.

---

## Tier 3 — Performance & Energy

### T3-1: DateFormatter created in view bodies (~20 files)

**Severity:** CRITICAL (SwiftUI performance)
**Component:** iOS app views

DateFormatter allocation costs ~1-2ms. Multiple views create formatters inside computed properties called from `var body`, meaning they fire on **every render**.

**Worst offenders:**

| File | Pattern | Frequency |
|------|---------|-----------|
| `SessionsView.swift:101` | `DateFormatter()` in `itemsByMonth` computed property | Every render of main session list |
| `ActivityGridView.swift:325` | `dateFormat` mutated inside loop (52 iterations) | Every Canvas draw call |
| `EventDetailView.swift:210-238` | 3 separate formatters in helper functions | Every render |
| `POTAJobViews.swift:271` | `formattedDate()` called 4x per row | 40 formatters for 10 jobs |
| `DXpeditionsView.swift:51` | `monthYearLabel` called twice in body | Every arrow tap |
| `EventsView.swift:298` | `formattedStartDate` computed property | Per event row |
| `BandTimelineView.swift:126` | `formatTime()` called in body + per segment | During scrolling |
| `ConditionsCard.swift:198-211` | 2 formatters in loop helpers | 60+ allocations per render |
| `MapDataLoadingActor.swift:255` | Formatter created inside `for item in allMetadata` loop | Multi-second map load stall |
| `BackupSettingsView.swift:277` | `formattedDate` computed property | Every render |

**Recommended fix:** Replace all with `private static let` formatters:

```swift
private static let monthGroupFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMMM yyyy"
    fmt.timeZone = TimeZone(identifier: "UTC")
    return fmt
}()
```

---

### T3-2: Zero timer tolerance on ALL timers

**Severity:** CRITICAL (Energy)
**Component:** iOS app services
**Files:**
- `SpotCommentsService.swift:59` — 60s poll, no tolerance
- `CloudSyncService.swift:146` — 30s poll, no tolerance
- `LoggingSessionManager+Spotting.swift:57` — poll timer
- `KiwiSDRAudioEngine.swift:240,271` — 0.1s and 0.5s timers
- `FT8SessionManager.swift:305,317` — cycle timers
- `SessionsView+Actions.swift:486` — maintenance timer
- `POTAActivationsView+Actions.swift:146` — maintenance timer

Without tolerance, the OS must wake the CPU at the exact requested time, preventing timer coalescing. Combined with 5+ concurrent polling loops during active logging, estimated 18-40% extra battery drain/hour.

**Recommended fix:** Add `.tolerance = interval * 0.1` after every `Timer.scheduledTimer` call. The CloudSync 30s timer, spot 60s timer, and maintenance 60s timers have zero latency requirement.

---

### T3-3: CloudSync polls iCloud every 30s redundantly

**Severity:** CRITICAL (Energy)
**Component:** iOS app services
**Files:** `CarrierWave/Services/CloudSync/CloudSyncService.swift:142-157`

`startActiveSessionPolling()` fires `fetchChangesFromCloud()` every 30 seconds. CKSyncEngine already supports push delivery via `remote-notification` background mode (declared in Info.plist). The existing `handleRemoteNotification` path makes this polling redundant.

**Recommended fix:** Remove the timer-based polling entirely. Rely on push-triggered fetches via `handleRemoteNotification`.

---

### T3-4: SpotMonitoringService — 5 concurrent network fetches every 45s

**Severity:** CRITICAL (Energy)
**Component:** iOS app services
**Files:** `CarrierWave/Services/SpotMonitoringService.swift:145,189`

`pollLoop()` and `hunterPollLoop()` fire 5 concurrent `async let` network fetches (RBN + POTA + SOTA + WWFF + PSK Reporter) every 45 seconds. This is the single most expensive pattern in the app. Combined with `FrequencyActivityService` at `CarrierWave/Services/FrequencyActivityService.swift:138` adding another RBN poll every 30s when the frequency panel is open.

**Estimated impact:** 20-40% extra drain during active logging or hunter mode.

**Recommended fix:** Increase hunter poll interval to 60-90s with tolerance. Share RBN fetches between `SpotMonitoringService` and `FrequencyActivityService` to avoid redundant calls. Add `URLSessionConfiguration` with `allowsConstrainedNetworkAccess = false` for non-interactive fetches.

---

### T3-5: Search without debounce in park/WWFF pickers

**Severity:** HIGH (SwiftUI performance)
**Component:** iOS app views
**Files:**
- `CarrierWave/Views/Logger/ParkPickerSheet.swift:109-111,230-244`
- `CarrierWave/Views/Logger/WWFFReferencePickerSheet.swift:97-99`

`onChange(of: searchText)` calls `performSearch()` synchronously on every keystroke with no debounce. The search performs a full-text scan of thousands of park entries on the main thread.

**Recommended fix:**

```swift
.onChange(of: searchText) { _, newValue in
    searchTask?.cancel()
    searchTask = Task {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        performSearch(query: newValue)
    }
}
```

---

### T3-6: Observer token leaks (3 instances)

**Severity:** HIGH (Memory)
**Component:** iOS app services

| File | Issue |
|------|-------|
| `Services/NeedsSpotNotifier.swift:215` | `addObserver(forName: .didLogQSO)` — return token discarded, observer accumulates on each navigation to ActivityLogView |
| `Services/FT8AudioEngine.swift:314` | `interruptionObserver` stored in property but no `deinit` removes it |
| `Services/ICloudMonitor.swift:65` | Selector-based observers never removed in `stopMonitoring()` or `deinit` |

**Recommended fix:** Store tokens and remove in `deinit`:

```swift
private var qsoObserver: (any NSObjectProtocol)?

func observeQSOLogging() {
    qsoObserver = NotificationCenter.default.addObserver(forName: .didLogQSO, ...) { ... }
}

deinit {
    if let token = qsoObserver { NotificationCenter.default.removeObserver(token) }
}
```

For `ICloudMonitor`, add `NotificationCenter.default.removeObserver(self)` to both `stopMonitoring()` and `deinit`.

---

### T3-7: `FT8AudioEngine.stop()` never deactivates audio session

**Severity:** HIGH (Energy)
**Component:** iOS app services
**Files:** `CarrierWave/Services/FT8AudioEngine.swift:63-70`

`configure()` calls `session.setActive(true)` but `stop()` only calls `engine.stop()` — never `AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)`. The audio hardware stays powered after FT8 ends.

**Recommended fix:** Add `try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)` to `stop()`.

---

### T3-8: `SessionsView.allItems` recomputes filter + sort on every render

**Severity:** MEDIUM (SwiftUI performance)
**Component:** iOS app views
**Files:** `CarrierWave/Views/Sessions/SessionsView.swift:93-113`

`allItems` is a computed property that calls `.filter`, `.map`, `.sorted` on the full sessions collection. Then `itemsByMonth` groups those results with a `DateFormatter` allocation. This entire chain fires on every render of the main session list.

**Recommended fix:** Cache `allItems` and `itemsByMonth` in `@State` properties, recomputed only when `sessions` or `orphanActivations` change via `.onChange`.

---

### T3-9: `FetchDescriptor<ActivationMetadata>` without `fetchLimit`

**Severity:** HIGH (SwiftUI performance)
**Component:** iOS app views
**Files:** `CarrierWave/Views/POTAActivations/POTAActivationsView.swift:350-363`

```swift
func loadMetadata() {
    let descriptor = FetchDescriptor<ActivationMetadata>()  // unbounded!
    let allMetadata = (try? modelContext.fetch(descriptor)) ?? []
```

While `ActivationMetadata` is not `QSO`, heavy activators can accumulate thousands of records. This runs on view appear.

**Recommended fix:** Add `fetchLimit` sized to the visible activations set, or move to a background actor.

---

### T3-10: Shadow rendering on 7+ logger panel views

**Severity:** MEDIUM (Energy)
**Component:** iOS app views
**Files:**
- `Views/Logger/RBNPanelView.swift:100`
- `Views/Logger/POTASpotsView.swift:157`
- `Views/Logger/WeatherPanelView.swift:35`
- `Views/Logger/P2PPanelView.swift:51`
- `Views/Logger/SolarPanelView.swift:44`
- `Views/Logger/WebSDRPanelView.swift:67`
- `Views/Logger/SessionMapPanelView.swift:35`

All 7 logger panels use `.shadow(color: .black.opacity(0.1), radius: 8, y: 2)` with live-updating spot data. The GPU redraws the shadow pass on every spot refresh (every 45 seconds × 7 panels).

**Recommended fix:** Apply `.drawingGroup()` to shadow layers, or separate static shadow chrome from dynamic content.

---

### T3-11: `ObservableObject` → `@Observable` migration candidates

**Severity:** MEDIUM (SwiftUI performance)
**Component:** iOS app services
**Files:**
- `Services/ICloudMonitor.swift`
- `Services/POTAAuthService.swift`
- `Services/ActivitiesSyncService.swift`
- `Services/FriendsSyncService.swift`
- `Views/Events/EventsView.swift:318` (EventLocationManager)

These services use `ObservableObject/@Published`, which causes over-rendering when **any** `@Published` property changes. `@Observable` tracks at the property level, so only views reading the changed property re-render. Most noticeable on `DashboardView` which observes both `iCloudMonitor` and `potaAuth`.

---

### T3-12: Pervasive `URLSession.shared` without configuration

**Severity:** MEDIUM (Energy)
**Component:** iOS app services
**Files:** 30+ call sites across QRZClient, POTAClient, ActivitiesClient, etc.

All network calls use `URLSession.shared` with no `waitsForConnectivity`, no `allowsExpensiveNetworkAccess` constraint, no `allowsConstrainedNetworkAccess`. On cellular, background fetches happily use the expensive radio. On poor WiFi, immediate failures cause rapid retry loops.

**Recommended fix:** Create a dedicated `URLSession` for non-interactive fetches with:
```swift
config.waitsForConnectivity = true
config.allowsConstrainedNetworkAccess = false
config.allowsExpensiveNetworkAccess = false
```

---

## Tier 4 — Operational Maturity

### T4-1: No crash monitoring or post-deploy alerting

**Severity:** HIGH
**Component:** CI/CD pipeline

No Sentry, Crashlytics, or documented App Store Connect crash monitoring workflow. No alerting on crash rate spikes after a release. TestFlight feedback is not actively triaged. A release causing widespread crashes would only surface through user complaints or incidental App Store Connect checks.

---

### T4-2: No log aggregation on server

**Severity:** HIGH
**Component:** Hetzner infrastructure

Logs go to systemd journal only on the single VPS. No Loki, ELK, or retention policy. No way to search logs historically without SSH access. No structured JSON logging — `tracing_subscriber::fmt::layer()` outputs human-readable text.

---

### T4-3: Health check doesn't verify database connectivity

**Severity:** MEDIUM
**Component:** Server + Hetzner
**Files:**
- `~/projects/activities-server/src/handlers/health.rs`
- `~/projects/hetzner/roles/monitoring/templates/checks.d/activities-server.sh.j2`

`/v1/health` returns `{"status":"ok"}` even if Postgres is down. The Hetzner monitoring script checks `/` (the SPA), not the health endpoint. A running but database-disconnected server passes all health checks.

---

### T4-4: Version maintained in 3 places manually

**Severity:** MEDIUM
**Component:** CI/CD pipeline
**Files:**
- `*.pbxproj` (`MARKETING_VERSION`)
- `SettingsView.swift` (hardcoded string)
- `CHANGELOG.md`

No script validates consistency. No CI check ensures the three values match. The release script only validates the git tag doesn't already exist.

---

### T4-5: 5 max database connections

**Severity:** MEDIUM
**Component:** Server
**Files:** `~/projects/activities-server/src/main.rs` (PgPoolOptions)

With concurrent HTTP requests + background aggregators + snapshot loop sharing the pool, connection starvation is possible under moderate load. No data on when the system breaks.

---

### T4-6: No certbot renewal automation visible

**Severity:** MEDIUM
**Component:** Hetzner infrastructure

Let's Encrypt certs expire in 90 days. No renewal timer or cron job visible in the Ansible config. Certificates may expire silently. (Note: certbot may self-install a systemd timer — verify on the host.)

---

### T4-7: CarrierWaveData has effectively no tests

**Severity:** MEDIUM
**Component:** iOS app tests
**Files:** `CarrierWaveData/Tests/` — 1 placeholder file

The shared data layer handles SwiftData models, cloud sync, and persistence. It has essentially zero test coverage. CarrierWaveCore (49 Swift Testing files) and CWSweep (17 files) have strong coverage. iOS app tests (36 XCTest files) are solid but legacy.

---

### T4-8: Swift 6 concurrency readiness

**Severity:** MEDIUM
**Component:** iOS app concurrency

Multiple patterns will error under `-strict-concurrency=complete`:

| Pattern | Files | Issue |
|---------|-------|-------|
| Missing `@MainActor` on `@Observable`/`ObservableObject` | `EventLocationManager`, `ParkLocationManager`, `WeatherPanelView.LocationManager` | `@Published` writes from delegate callbacks |
| Strong `self` in `Task { @MainActor in }` from `nonisolated` | `CloudSyncService`, `GridLocationService`, `CompassHeadingService`, 6+ files | "Sending self risks data races" |
| `@unchecked Sendable` on derivable structs | `HAMRSModels.swift`, `ChallengeTypes.swift`, `POTAClient.swift` (20+ types) | Suppresses compile checks unnecessarily |

**Recommended fix:** Enable `-strict-concurrency=complete` as warnings first. Fix `@MainActor` annotations and `[weak self]` captures. Remove unnecessary `@unchecked Sendable`.

---

### T4-9: Dockerfile references wrong binary name

**Severity:** LOW
**Component:** Server
**Files:** `~/projects/activities-server/Dockerfile:41`

References `challenges-server` while `Cargo.toml` names the package `activities-server`. The Docker build path appears unused/broken.

---

### T4-10: No request-level tracing/correlation IDs on server

**Severity:** LOW
**Component:** Server

`TraceLayer` from `tower_http` is present but no span enrichment (request ID, callsign, etc.) is applied. If two requests fail simultaneously, there is no way to distinguish their log entries.

---

## Strengths Confirmed

The audit also confirmed several areas of strong engineering:

### iOS App
- Credentials properly stored in Keychain — no `@AppStorage` for secrets
- No hardcoded credentials in source code
- HTTPS for all sensitive API endpoints (QRZ, POTA, LoTW, eQSL, Activities)
- Privacy Manifests present for main app and widget extension
- `@Query` correctly banned for QSO/ServicePresence tables
- Good timer lifecycle management (invalidate in `onDisappear`)
- Proper `[weak self]` in most closures
- `AnyCancellable` for Combine subscriptions
- Strong test code quality: no `sleep()`, no shared mutable state, no flaky patterns
- CarrierWaveCore has excellent Swift Testing adoption (49 files)

### Server
- Typed error handling with `thiserror` and proper `IntoResponse` mapping
- Compile-time SQL checking with sqlx
- Prometheus metrics for HTTP, DB pool, GIS, and RBN
- Feature flags for every subsystem
- CI pipeline with lint, unit tests, and E2E tests
- Grafana annotations on deploy and CI failures
- Input clamping on query parameters
- ETag support for club sync
- RBN ingester has exponential backoff

### Infrastructure
- UFW with default deny, only SSH/HTTP/HTTPS open
- fail2ban for SSH brute force protection
- Let's Encrypt with modern TLS configuration
- DH parameters generated at 2048-bit
- Health monitoring with ntfy push notifications

---

## Action Plan

### Week 1 — Stop the bleeding (est. 3 hours)

| # | Task | Est. | Risk |
|---|------|------|------|
| 1 | Set up `pg_dump` cron with off-site backup | 30 min | Data loss prevention |
| 2 | Commit `Cargo.lock` to activities-server | 5 min | Build reproducibility |
| 3 | Add Xcode Cloud test + PR workflow | 1 hr | CI coverage |
| 4 | Fix ATS to domain-specific exceptions | 30 min | App Store risk |
| 5 | Add timer tolerance to all timers | 30 min | Battery drain |

### Week 2 — Harden (est. 4 hours)

| # | Task | Est. | Risk |
|---|------|------|------|
| 6 | Fix `nonisolated(unsafe)` with `NSLock` | 2 hr | Data races / crashes |
| 7 | Fix 3 observer token leaks | 30 min | Memory leaks |
| 8 | Add constant-time token comparison | 15 min | Timing attack |
| 9 | Vault the ntfy password | 15 min | Secret exposure |
| 10 | Add graceful shutdown to server | 1 hr | Request loss on deploy |

### Sprint 3 — Performance (est. 4 hours)

| # | Task | Est. | Risk |
|---|------|------|------|
| 11 | Cache all DateFormatters as `static let` | 2 hr | UI stutter |
| 12 | Add debounce to park/WWFF search | 30 min | Main thread blocking |
| 13 | Remove redundant CloudSync polling timer | 30 min | Battery drain |
| 14 | Add `setActive(false)` to FT8AudioEngine.stop() | 5 min | Audio hardware power |
| 15 | Add keychain accessibility attributes | 15 min | Credential protection |
| 16 | Replace debug prints with os.Logger | 15 min | Log hygiene |

### Sprint 4 — Operational maturity (est. 6 hours)

| # | Task | Est. | Risk |
|---|------|------|------|
| 17 | Add rate limiting to server | 1 hr | Abuse prevention |
| 18 | Set up crash monitoring workflow | 1 hr | Silent regressions |
| 19 | Add log aggregation (Loki or similar) | 2 hr | Debugging capability |
| 20 | Fix health endpoint to check DB | 30 min | Monitoring accuracy |
| 21 | Begin `ObservableObject` → `@Observable` migration | 2+ hr | Over-rendering |
| 22 | Enable `-strict-concurrency=complete` warnings | 1 hr | Swift 6 prep |

---

## Files Examined

Full file lists are recorded in each agent's output. Key files by finding:

| File | Finding |
|------|---------|
| `CarrierWave/Info.plist` | ATS wide open, background modes |
| `CarrierWaveData/.../KeychainHelper.swift` | Missing accessibility, shared group too permissive |
| `CarrierWave/Utilities/KeychainHelper+Migration.swift` | Debug prints, accessibility |
| `CarrierWave/Services/POTAParksCache.swift` | `nonisolated(unsafe) var` data race |
| `CarrierWave/Services/SOTASummitsCache.swift` | `nonisolated(unsafe) var` data race |
| `CarrierWave/Services/WWFFReferencesCache.swift` | `nonisolated(unsafe) var` data race |
| `CarrierWave/Services/CallsignNotesCache.swift` | `nonisolated(unsafe) var` data race |
| `CarrierWave/Services/CloudSync/CloudSyncService.swift` | Redundant 30s poll, strong self capture |
| `CarrierWave/Services/SpotMonitoringService.swift` | 5 concurrent fetches every 45s |
| `CarrierWave/Services/SpotCommentsService.swift` | 60s poll, no tolerance |
| `CarrierWave/Services/FT8AudioEngine.swift` | No setActive(false), observer leak |
| `CarrierWave/Services/NeedsSpotNotifier.swift` | Observer token discarded |
| `CarrierWave/Services/ICloudMonitor.swift` | Observers never removed |
| `CarrierWave/Views/Sessions/SessionsView.swift` | DateFormatter in body, allItems recompute |
| `CarrierWave/Views/Dashboard/ActivityGridView.swift` | Format mutated in Canvas loop |
| `CarrierWave/Views/Events/EventDetailView.swift` | 3 formatters per render |
| `CarrierWave/Views/Events/EventsView.swift` | Formatter + missing @MainActor on LocationManager |
| `CarrierWave/Views/Logger/ParkPickerSheet.swift` | No search debounce |
| `CarrierWave/Views/Logger/WWFFReferencePickerSheet.swift` | No search debounce |
| `CarrierWave/Views/POTAActivations/POTAActivationsView.swift` | Unbounded FetchDescriptor |
| `CarrierWave/Views/Map/MapDataLoadingActor.swift` | Formatter in loop |
| `.github/workflows/ci.yml` | Lint-only, no macOS runner |
| `ci_scripts/ci_post_clone.sh` | Only installs SwiftLint |
| `~/projects/activities-server/src/main.rs` | No graceful shutdown, 5 DB connections |
| `~/projects/activities-server/src/auth/middleware.rs` | Non-constant-time token comparison |
| `~/projects/activities-server/.gitignore` | Cargo.lock excluded |
| `~/projects/hetzner/roles/monitoring/defaults/main.yml` | Unvaulted ntfy password |

---

## Lessons Learned

1. **Timer tolerance is a one-line fix with outsized impact.** Every `Timer.scheduledTimer` should be immediately followed by `.tolerance = interval * 0.1`. Consider a lint rule or wrapper.

2. **`nonisolated(unsafe)` is the Swift concurrency equivalent of `force_unwrap`.** It silences the compiler but doesn't fix the race. When you need synchronous reads from an actor, use a lock.

3. **CI that only lints is CI that lies.** Code that passes lint but doesn't compile ships to TestFlight unchecked. The minimum viable iOS CI needs: lint + build + unit tests, on PRs.

4. **Database backups are table stakes.** The server has Prometheus metrics, Grafana annotations, and health checks — but no recovery path for the data those systems monitor.

5. **DateFormatter is one of the most expensive objects in Foundation.** The pattern of creating one in a computed property that feeds `var body` is a SwiftUI anti-pattern that should be caught by a lint rule or code review checklist.
