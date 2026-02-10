# Persistent Activity Log ("Hunted Log") Design

**Linear:** CAR-47
**Status:** Draft
**Date:** 2026-02-10
**UI Mockups:** [Activity Log UI Mockups](2026-02-10-activity-log-ui-mockups.md)

## Problem

Current logging sessions are activation-centric: start a session, operate from a location, end the session, upload. This works well for POTA/SOTA activators but doesn't fit the "hunter" workflow: sitting at home (or mobile), chasing spots across bands, logging contacts as they come throughout the day.

Hunters need a persistent log that:
- Stays open across app launches (no start/end ceremony)
- Tracks daily QSO count as a running tally
- Surfaces POTA/SOTA/RBN spots as the primary workflow driver
- Uploads QSOs incrementally (to QRZ, LoFi) rather than in a batch
- Records location changes when the operator moves (mobile, portable)

## Core Concept: Activity Log vs. Activation Session

| Aspect | Activation Session (existing) | Activity Log (new) |
|--------|-------------------------------|---------------------|
| Lifecycle | Explicit start/end | Always open, daily segments |
| Location | Fixed (one park/summit) | Can change (home, mobile, portable) |
| Primary action | Enter callsign | Tap a spot |
| Sync trigger | End of session or manual | Per-QSO (as you go) |
| POTA upload | Yes (grouped by park) | No (no operator park ref) |
| Counter scope | Session total | Daily total |
| Band/mode | Set at start, update manually | Follows spots, changes frequently |

The activity log is **not a replacement** for activation sessions. It's a separate mode. Users can have an activity log open AND start a POTA activation (which pauses the activity log context).

## Data Model

### Option A: New `ActivityLog` Model (Recommended)

A new SwiftData model separate from `LoggingSession`, purpose-built for the persistent workflow:

```swift
@Model
final class ActivityLog {
    var id: UUID
    var myCallsign: String
    var createdAt: Date

    /// Current station profile (JSON-encoded StationProfile)
    var stationProfileData: Data?

    /// Current grid square (updated on location change)
    var currentGrid: String?

    /// Last known location description (e.g., "Home", "Mobile - I-95")
    var locationLabel: String?

    /// Whether this is the active activity log
    var isActive: Bool
}
```

QSOs logged from the activity log still use the existing `QSO` model. They link back via `loggingSessionId` set to the activity log's UUID (reusing the existing field) or a new `activityLogId` field.

**Why not reuse `LoggingSession`?** The lifecycles are fundamentally different. LoggingSession has `startedAt`/`endedAt`, activation types, park references. Forcing a "never-ending session" into that model creates awkward edge cases everywhere (dashboard stats, POTA activation grouping, session history).

### Station Profiles

Reusable station configurations the user defines once and swaps between. Follows the same `UserDefaults`-backed storage pattern as `RadioStorage` (used by `RadioPickerSheet`).

```swift
/// UserDefaults-backed storage, mirrors RadioStorage pattern
enum StationProfileStorage {
    static func load() -> [StationProfile] { ... }
    static func save(_ profiles: [StationProfile]) { ... }
    static func add(_ profile: StationProfile) { ... }
    static func remove(_ id: UUID) { ... }
    static func defaultProfile() -> StationProfile? { ... }
}

struct StationProfile: Codable, Identifiable {
    var id: UUID
    var name: String          // "Home QTH", "Mobile", "QRP Portable"
    var power: Int?           // Watts
    var rig: String?          // "IC-7300", "KX3" — selected via existing RadioPickerSheet
    var antenna: String?      // "Hex beam", "EFHW"
    var grid: String?         // Default grid for this profile
    var useCurrentLocation: Bool  // If true, grid comes from CoreLocation instead of fixed value
    var isDefault: Bool       // Auto-selected when opening activity log
}
```

Storage: JSON-encoded array in `UserDefaults` under key `"stationProfiles"`. This matches the `RadioStorage` pattern — simple, no SwiftData migration needed, profiles are small user-managed data. The radio field (`rig`) reuses the existing `RadioPickerSheet` for selection rather than duplicating that UI.

When the user opens the activity log, the default profile is loaded. They can switch profiles from a picker (e.g., arriving at a park for casual operating, switching from "Home" to "Portable").

### Daily Segments

The activity log doesn't reset, but it tracks daily boundaries:

```swift
struct DailySegment {
    let date: Date            // Start of day (UTC)
    let qsoCount: Int
    let bandsWorked: Set<String>
    let modesUsed: Set<String>
    let newDXCC: [Int]        // DXCC entities first worked today
}
```

These are computed from QSOs, not stored. The UI shows today's segment prominently with historical segments accessible via scrolling.

## UI Design

### Entry Point

Add "Activity Log" as a new activation type in `SessionStartSheet`, OR provide a dedicated entry from the Dashboard/Logger tab. Recommendation: **dedicated entry** - a persistent button/card on the Dashboard that says "Activity Log" with today's count, distinct from the "Start Session" flow.

### Main View: Spot-First Layout

```
┌─────────────────────────────────┐
│ Activity Log         📍 EM85    │
│ Today: 12 QSOs  |  3 bands     │
│ Home QTH - IC-7300 100W  [⚙]  │
├─────────────────────────────────┤
│ ┌─ Spots ──────────────────── ┐ │
│ │ 🟢 W4DOG  14.062 CW  POTA  │ │  ← Tap to log
│ │    K-1234  2m ago           │ │
│ │ 🔵 N5RZ   7.030  CW  RBN   │ │
│ │    22 dB   5m ago           │ │
│ │ 🟢 KG5YOW 14.061 CW  POTA  │ │
│ │    K-5678  1m ago  ✓ 20m    │ │  ← "✓ 20m" = already worked
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ ┌─ Quick Log ─────────────── ┐  │
│ │ [Callsign] [RST] [Log it]  │  │  ← Manual entry still available
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ Recent QSOs                     │
│  14:32  W4DOG   20m CW  K-1234 │
│  14:28  N5RZ    40m CW         │
│  14:15  KE8OGR  20m CW  K-9012 │
└─────────────────────────────────┘
```

Key differences from current logger:
1. **Spots panel is primary** (top of screen, not behind a command)
2. **Worked-before badges** on spots (checkmark + band list)
3. **Station profile banner** with quick-swap gear icon
4. **Daily counter** always visible
5. **Callsign entry is secondary** (collapsed or at bottom)

### Tap-to-Log from Spot

Tapping a spot should:
1. Set frequency and mode from the spot
2. Pre-fill the callsign
3. Pre-fill their park reference (if POTA spot)
4. Show the QSO form with RST fields
5. One tap to confirm and log

This is the fastest path. The goal is: see spot -> tap -> confirm -> logged, in under 3 seconds.

### Location Change Prompt

When the app is reopened and the activity log is active, check if location has changed significantly (>10km via CoreLocation, or grid square changed). If so, prompt:

```
┌────────────────────────────────┐
│  📍 Location changed           │
│  New grid: EM84 (was EM85)     │
│                                │
│  [Update Grid]  [Keep EM85]   │
│                                │
│  Switch profile?               │
│  [Home QTH] [Mobile] [Other]  │
└────────────────────────────────┘
```

This keeps the log going but records the grid change so QSOs have accurate `myGrid` values.

### Station Profile Picker

Accessible from the gear icon on the activity log header:

```
┌────────────────────────────────┐
│  Station Profile               │
│                                │
│  ● Home QTH                   │
│    IC-7300 · 100W · Hex beam  │
│    EM85                        │
│                                │
│  ○ Mobile                      │
│    IC-705 · 10W · Hamstick    │
│                                │
│  ○ QRP Portable                │
│    KX3 · 5W · EFHW            │
│                                │
│  [+ Add Profile]               │
└────────────────────────────────┘
```

Switching profiles updates power, rig, antenna, and optionally grid for subsequent QSOs. Previous QSOs retain their original profile values.

## Worked-Before Detection

This is the killer feature for hunters. For every callsign visible in the spot list:

1. Check the current day's QSOs: "worked today on 20m CW"
2. Check all-time QSOs: "worked before on 40m, 20m"
3. Check DXCC: "new DXCC entity!" flag

Implementation:
- On activity log open, build an in-memory dictionary: `[String: Set<String>]` mapping callsign -> set of bands worked today
- For all-time, use a background query limited to the specific callsigns visible in the spot list (not a full table scan)
- Update the dictionary as QSOs are logged
- Display as badges on spot rows

```swift
actor WorkedBeforeCache {
    /// Bands worked today for each callsign
    private var todayWorked: [String: Set<String>] = [:]

    /// Bands worked all-time for each callsign (lazy-loaded per callsign)
    private var allTimeWorked: [String: Set<String>] = [:]

    func workedToday(_ callsign: String) -> Set<String>
    func workedAllTime(_ callsign: String) -> Set<String>
    func recordQSO(callsign: String, band: String)
}
```

## Sync Behavior

QSOs from the activity log:
- **QRZ**: Upload immediately (same as activation sessions)
- **LoFi**: Upload immediately
- **POTA**: **Never** - no operator park reference. The contacted station's park ref (`theirParkReference`) is still recorded for stats but the QSO isn't a POTA activation log
- **LoTW**: Follow existing rules (download only)

The `markForUpload` logic already handles this correctly: POTA upload is gated on `activeSession?.activationType == .pota`. For the activity log, we need equivalent gating that skips POTA.

## Spot Sources & Filtering

The activity log should aggregate spots from:

1. **POTA spots** - All active POTA activators (not just user's park). This is the primary spot source for hunters.
2. **RBN spots** - Reverse Beacon Network for CW/FT8/RTTY stations
3. **SOTA spots** - (Future) SOTAwatch spots for summit activators

Filtering options:
- **Band**: Show only spots on bands I can work (based on current antenna/profile)
- **Mode**: CW only, SSB only, digital only, all
- **Source**: POTA, RBN, SOTA, or all
- **Region**: DX only, NA only, all (using SpotRegion)
- **Worked status**: Hide already-worked, show all

The existing `SpotMonitoringService` and `SpotsService` already fetch combined RBN + POTA spots. The activity log UI would use these same services but with broader filtering (current logger filters to user's own callsign for "being spotted" - the activity log wants "all spots" or "spots matching my interests").

## Relationship to Existing Logger

The activity log reuses:
- `QSO` model (with `activityLogId` or reusing `loggingSessionId`)
- `SyncService` for uploads
- `SpotsService` / `SpotMonitoringService` for spot data
- `CallsignLookupService` for callsign info cards
- Keyboard accessory and quick entry parser

It does NOT reuse:
- `LoggingSession` model (different lifecycle)
- `SessionStartSheet` (no activation type, park ref, etc.)
- Auto-spot / QSY spot / QRT spot logic (not activating)
- `POTAUploadPromptSheet` (no POTA upload)
- Spot comments polling (not relevant for hunters)

## Settings

Under Settings > Activity Log:
- **Station Profiles**: Manage profiles (add, edit, delete, set default)
- **Spot Preferences**: Default band/mode/source filters
- **Daily Goal**: Optional QSO target (triggers notification/badge at goal)
- **Upload Behavior**: Which services to auto-upload to (default: QRZ + LoFi)
- **Location Tracking**: Enable/disable location change detection

## Implementation Phases

### Phase 1: Core Activity Log
- `ActivityLog` SwiftData model
- Basic UI with manual callsign entry
- Daily counter
- Station profiles (power, rig, grid)
- QRZ/LoFi upload integration

### Phase 2: Spot-Driven Workflow
- Spot list as primary UI element (POTA + RBN)
- Tap-to-log from spots
- Spot filtering (band, mode, source)
- Worked-before badges

### Phase 3: Location & Intelligence
- CoreLocation integration for grid updates
- Location change prompts on reopen
- DXCC new-entity highlighting
- Daily goal tracking
- Band hopping timeline

### Phase 4: Polish
- Share cards for daily activity ("12 QSOs today, 4 new DXCC")
- Historical daily segments view
- Integration with activity feed
- Statistics integration (hunter stats vs activator stats)

## Files to Create/Modify

### New Files
| File | Purpose |
|------|---------|
| `Models/ActivityLog.swift` | ActivityLog SwiftData model |
| `Models/StationProfile.swift` | Station profile struct + storage |
| `Views/ActivityLog/ActivityLogView.swift` | Main activity log view |
| `Views/ActivityLog/ActivityLogSpotsList.swift` | Spot list with worked-before badges |
| `Views/ActivityLog/ActivityLogHeader.swift` | Daily counter + station profile banner |
| `Views/ActivityLog/StationProfilePicker.swift` | Profile selection sheet |
| `Views/ActivityLog/ActivityLogSettingsView.swift` | Activity log settings |
| `Services/WorkedBeforeCache.swift` | Worked-before detection actor |
| `Services/ActivityLogManager.swift` | Activity log lifecycle management |

### Modified Files
| File | Change |
|------|--------|
| `CarrierWaveApp.swift` | Add ActivityLog to SwiftData schema |
| `ContentView.swift` | Add activity log entry point |
| `DashboardView.swift` | Add activity log card with daily count |
| `SyncService+Upload.swift` | Handle activity log QSO uploads (skip POTA) |
| `QSO.swift` | Add `activityLogId` field (or reuse `loggingSessionId`) |
| `SettingsView.swift` | Add activity log settings section |
| `SpotMonitoringService.swift` | Support broader "all spots" mode for hunters |

## Open Questions

1. **Tab vs. in-logger toggle?** Should the activity log be a separate tab, a mode within the existing Logger tab, or accessible from Dashboard? Recommendation: mode within Logger tab, toggled via a segmented control or long-press on the "Start Session" button.

2. **One activity log or many?** Should there be exactly one persistent activity log, or can users create multiple (e.g., "Home CW Hunting", "Contest Logging")? Recommendation: start with exactly one, add named logs later if needed.

3. **Antenna field?** Station profiles include antenna. Is this worth tracking in ADIF (there's no standard ADIF field for antenna, though `MY_ANTENNA` exists as a non-standard extension)? Recommendation: store locally for display but don't include in ADIF exports. *(Note: `MY_ANTENNA` is actually in the ADIF 3.1.4 spec — could include it if services accept it.)*

4. **Interaction with active POTA session?** If the user has an activity log open and starts a POTA session, what happens? Recommendation: POTA session takes over the logger UI. Activity log state is preserved but dormant. When POTA session ends, activity log resumes.

5. **Historical data import?** Should QSOs already in the database (from QRZ/LoFi imports) count toward worked-before detection? Yes - this is essential for the feature to be useful from day one.
