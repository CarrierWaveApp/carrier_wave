# Investigation: Silent App Exit Mid-Session (W4DHW)

**Date:** 2026-04-23, updated 2026-04-24
**Reporter:** W4DHW
**Symptom:** App exits to Home Screen mid-session without crash dialog. Happens every session. No pop-up — just quits. Must relaunch, reopen session, manually re-add missed QSOs.

## User Profile (from follow-up)

- **Session type:** POTA activation
- **No BLE radio, No WebSDR, No CW transcription**
- **Screen active the whole time** — NOT a background transition
- **~30 minutes into session** (roughly consistent)
- **Only 20-25 total QSOs** (new/casual user)
- **Device:** unknown

## Investigation Method

Five parallel agents investigated: memory pressure, background transitions, CPU watchdog, SwiftData concurrency, and resource exhaustion. A second round of three focused agents investigated the specific POTA activation + 30-minute timing pattern.

## Critical Discovery: PollingCoordinator Is Broken

**File:** `PollingCoordinator.swift:139-141`

```swift
if let existing = runningTasks[id], !existing.isCancelled {
    continue  // skip this registration
}
```

Completed tasks are never removed from `runningTasks`. Since `Task.isCancelled` returns `false` for a completed (never-cancelled) task, the skip-if-busy guard evaluates to `true` after every registration's first fire. **All PollingCoordinator-registered services stop polling after their first tick.** This means:

- SpotMonitoringService: fires ONCE, then stops
- SpotCommentsService: fires ONCE, then stops
- AutoSyncService: fires ONCE, then stops
- FrequencyActivityService: fires ONCE, then stops

Services with their **own timer loops** (not using PollingCoordinator) still fire:
- DONKIPollingService: own Task loop, **fires at exactly 30 minutes**
- ContestPollingService: own Task loop
- LoggingSessionManager auto-spot timer: `Timer.scheduledTimer`
- UTCDayBoundary timer: `Timer.scheduledTimer`

This bug has two consequences:
1. **Spots and comments go stale after 60 seconds** (functional bug)
2. **The 30-minute crash is NOT from polling accumulation** — eliminates the "cumulative spot data" theory

---

## Revised Root Cause Analysis

With PollingCoordinator broken and the user profile narrowed, the remaining candidates for a ~30 minute silent exit during a POTA activation with screen active:

### P0 — Most Likely

#### F1. DONKIPollingService Fires at Exactly 30 Minutes
**File:** `DONKIPollingService.swift:56` — `pollingInterval: TimeInterval = 1_800`

DONKI runs its own Task loop (not PollingCoordinator) and fires at exactly 30 minutes. It makes 3 sequential NASA API calls, decodes JSON, updates `@Observable` state, and publishes `SpaceWeatherNotifier` notifications. On poor cell coverage (common in parks during POTA), these requests could time out sequentially.

While the API calls themselves are async (don't block main thread), the state updates hit `@MainActor @Observable` properties which trigger SwiftUI re-renders. If this coincides with other work, it could be the tipping point.

**However:** DONKI alone probably isn't enough to crash the app. It's more likely the *trigger* that pushes an already-stressed app past a threshold, not the sole cause.

#### F2. Memory Pressure from Baseline Caches + No Warning Handler
**Files:** `CarrierWaveApp.swift:260-271` (cache loading), entire codebase (no `didReceiveMemoryWarning`)

Even with only 25 QSOs, the app holds ~40-80 MB of permanent reference caches:
- POTAParksCache (~50K parks)
- SOTASummitsCache (~100K summits)
- WWFFReferencesCache (~40K references)
- SKCCMembershipStore (~30K members)
- SCPDatabase (~80K callsigns, duplicated in sorted array AND set)

These are loaded concurrently at startup and **never released**. With zero `didReceiveMemoryWarning` handling, the app cannot shed load when iOS warns of pressure. On a 4 GB device running other apps, this baseline plus 30 minutes of SwiftData ModelContext graph growth could hit the jetsam threshold.

The ModelContext accumulates faulted objects from every fetch during the session — even though individual fetches are bounded, the context retains all materialized objects and never resets.

#### F3. Fresh POTAAuthService + Headless WKWebView Per Spot Post
**File:** `LoggingSessionManager+Spotting.swift:309`

```swift
let potaClient = POTAClient(authService: POTAAuthService())
```

Every `postSpot()` creates a new `POTAAuthService` with `currentToken = nil`, forcing a full headless `WKWebView` login flow. WKWebView's web content process retains memory even after the view is deallocated. If auto-spot is enabled (likely for a POTA activator), this creates a new headless WebView every 10 minutes. After 3 cycles (30 minutes), the leaked web content processes could contribute 30-50 MB to memory pressure.

**Combined with F2 (baseline caches), this could push total memory past the jetsam threshold at the ~30 minute mark.**

### P1 — Contributing Factors

#### F4. PollingCoordinator Skip-If-Busy Bug
**File:** `PollingCoordinator.swift:139-141`

As described above. This is independently a P0 functional bug (spots/comments/sync go stale after 60 seconds) but for the crash investigation, it actually *reduces* crash risk by preventing repeated polling. Must be fixed, but fixing it without also fixing the memory issues could make crashes happen *sooner*.

#### F5. Unbounded SessionSpot Fetch in recordSpots
**File:** `LoggingSessionManager+Spotting.swift:240-244`

```swift
let descriptor = FetchDescriptor<SessionSpot>(predicate: predicate)
// No fetchLimit!
let existing = (try? modelContext.fetch(descriptor)) ?? []
```

Violates the project's mandatory performance rule: "Always set `fetchLimit` on descriptors — no unbounded fetches, ever." This loads ALL session spots into the main ModelContext. However, with PollingCoordinator broken, `recordSpots` may only fire once, limiting the damage.

#### F6. No `beginBackgroundTask` Protection Anywhere
**Search result:** Zero calls to `beginBackgroundTask` or `BGTaskScheduler` in the entire codebase.

Any work in progress when the app briefly backgrounds (even from Control Center pull-down) is killed mid-execution. This can corrupt sync state and leave partial writes. Not the crash cause for this user (screen stays active), but a systemic risk.

### P2 — Ruled Out for This User (Still Valid Bugs)

| Finding | Why Ruled Out |
|---------|--------------|
| CWAudioCapture interruption handler | User doesn't use CW transcription |
| WebSDR reconnect in background | User doesn't use WebSDR |
| BLE radio polling at 200ms | No radio connected |
| QSO data volume scaling | Only 25 QSOs |
| Background/foreground resume burst | Screen stays active |

---

## Recommended Fix Priority

### Phase 1: Fix the Crash (F1-F3)

1. **Fix PollingCoordinator `runningTasks`** — clear completed tasks so polling actually works. Either nil out the entry after the action completes, or check for completion state:
   ```swift
   runningTasks[id] = Task {
       await action()
       await MainActor.run { runningTasks[id] = nil }
   }
   ```

2. **Add `didReceiveMemoryWarning` handler** — observe `UIApplication.didReceiveMemoryWarningNotification`, clear reference caches. They can be lazily reloaded on next access.

3. **Reuse existing POTAAuthService in `postSpot`** — don't create a fresh `POTAAuthService()` per call. Pass the app's existing instance or cache the token.

4. **Add `fetchLimit` to SessionSpot fetch in `recordSpots`** — or better, maintain an in-memory `Set<String>` of dedup keys instead of re-fetching.

### Phase 2: Robustness

5. Add `beginBackgroundTask` protection for CloudSync/ClubsSync resume work
6. Stagger PollingCoordinator resume (once it's working again) with jitter
7. Move SpotMonitoringService enrichment off `@MainActor`
8. Pause NWPathMonitor on background
9. Fix KiwiSDRClient URLSession leak on error paths
10. Fix BLE AsyncStream continuation leaks

### Phase 3: Observability

11. Log `os_proc_available_memory()` periodically via PerfUploader
12. Ensure MetricKit collects `MXDiagnosticPayload` for hang/crash diagnostics
13. Monitor `ProcessInfo.processInfo.thermalState`

---

## Probable Crash Sequence

```
T=0s     App launches, loads 40-80 MB of reference caches
T=2s     Stats pipeline, CloudSync, backup all start
T=5s     User opens POTA activation session
T=10s    PollingCoordinator fires all services ONCE, then stops (bug)
T=60s    First auto-spot timer fires → creates POTAAuthService + WKWebView (leaked)
T=600s   Second auto-spot → another WKWebView leaked (~15-20 MB added)
T=1200s  Third auto-spot → another WKWebView leaked (~30-40 MB added)
T=1800s  DONKI 30-min poll fires → 3 API calls + JSON decode + state updates
         → SwiftUI re-render burst coincides with elevated memory
         → Total memory: 40-80 MB caches + 30-40 MB WebView leaks
            + ModelContext graph + SwiftUI views = ~120-180 MB
         → iOS jetsam threshold exceeded on 4 GB device → SIGKILL
```

## What Would Confirm This

1. **Device model** — if it's a 4 GB RAM device (iPhone 12/13/SE), jetsam is very likely
2. **Is auto-spot enabled?** — determines if F3 (WKWebView leak) applies
3. **Analytics Data** — `jetsam-*` log would be definitive
4. **Add memory logging** — `os_proc_available_memory()` at spot post time would show the leak
