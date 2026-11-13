# Investigation: iOS Battery Drain

**Date:** 2026-03-28
**Status:** Resolved
**Outcome:** Fixed 5 categories of battery drain — timer tolerance, redundant CloudSync polling, aggressive spot monitoring, and reduced network frequency

## Problem Statement

User-reported terrible battery usage on iOS. Investigated all services, timers, GPS, network polling, and audio sessions for unnecessary energy consumption.

## Root Causes Found

### 1. Zero timer tolerance on ALL timers (CRITICAL)

Every `Timer.scheduledTimer` in the app had no `.tolerance`, forcing exact CPU wake-ups and preventing iOS timer coalescing. With 5+ concurrent timers during active logging, estimated 18-40% extra drain/hour.

**Fix:** Added `.tolerance = interval * 0.1` to all 10 timer instances.

### 2. CloudSync polls iCloud every 30s — redundantly (CRITICAL)

`CloudSyncService.startActiveSessionPolling()` fired `fetchChangesFromCloud()` every 30 seconds during active sessions. CKSyncEngine already supports push delivery via `remote-notification` background mode, making this entirely redundant.

**Fix:** Removed timer-based polling, `setupActiveSessionObserver`, and related infrastructure. Push-triggered fetches via `handleRemoteNotification` remain.

### 3. SpotMonitoringService — 5 concurrent fetches every 45s (CRITICAL)

`pollLoop()` and `hunterPollLoop()` fired RBN + POTA + SOTA + WWFF + PSK Reporter every 45s. `FrequencyActivityService` added another RBN poll every 30s. Single most expensive network pattern.

**Fix:** Increased SpotMonitoringService to 90s, FrequencyActivityService to 60s. Added `Task.sleep` tolerance to both.

### 4. FT8AudioEngine never deactivated audio session (HIGH)

Was already fixed prior to this investigation.

### 5. Remaining issues (not fixed in this pass)

- Continuous GPS during sessions (`LocationSessionService`) — intentional for grid tracking
- BLE scanning without service filter — only active with radio connected
- 30+ `URLSession.shared` call sites without constrained configuration
- `ObservableObject` over-rendering on Dashboard
- Shadow rendering on 7 logger panels

## Files Modified

| File | Change |
|------|--------|
| `CarrierWave/Services/SpotCommentsService.swift` | Added 6s tolerance to 60s poll timer |
| `CarrierWave/Services/CloudSync/CloudSyncService.swift` | Removed 30s polling timer + observer infrastructure |
| `CWSweep/CWSweep/Services/CloudSync/CloudSyncService.swift` | Removed polling timer reference |
| `CarrierWave/Services/LoggingSessionManager+Spotting.swift` | Added 10% tolerance to auto-spot timers |
| `CarrierWave/Services/WebSDR/KiwiSDRAudioEngine.swift` | Added tolerance to 0.1s and 0.5s timers |
| `CarrierWave/Services/FT8SessionManager.swift` | Added tolerance to slot (1.5s) and cycle (0.1s) timers |
| `CarrierWave/Services/WebSDR/WebSDRSession+Internals.swift` | Added 0.1s tolerance to 1s duration timer |
| `CarrierWave/Views/Sessions/SessionsView+Helpers.swift` | Added 6s tolerance to 60s maintenance timer |
| `CarrierWave/Services/SpotMonitoringService.swift` | 45s→90s interval + 9s tolerance |
| `CarrierWave/Services/FrequencyActivityService.swift` | 30s→60s interval + tolerance |

## Lessons Learned

- Every `Timer.scheduledTimer` should be immediately followed by `.tolerance = interval * 0.1`. Consider a lint rule or helper.
- Push-based sync (CKSyncEngine remote notifications) should always be preferred over polling.
- Network polling intervals should be reviewed holistically — multiple services polling independently compounds drain.
