# SOTA Spots + Multi-Program Sessions Design

**Date:** 2026-02-26
**Status:** Approved

## Summary

Add SOTA spots to both hunter log and logger, support dual POTA+SOTA sessions, and rename the POTA command to HUNT for the unified spots panel.

## Requirements

1. Users can select multiple operating programs (POTA, SOTA, both, or neither/casual) per session
2. SOTA spots from SOTAwatch API appear alongside POTA spots in a unified list
3. The `POTA` logger command is renamed to `HUNT` (with `POTA` as backward-compat alias)
4. UX is clean and Apple HIG-compliant

### Out of Scope (Phase 1)

- SOTA self-spotting
- S2S (summit-to-summit) detection
- SOTA log upload
- SOTA-specific statistics/brag sheet
- SOTA spot comments

## Data Model

### OperatingProgram

Replace the single-select `ActivationType` enum with a set-based model:

```swift
enum OperatingProgram: String, Codable, CaseIterable, Comparable {
    case pota, sota

    var displayName: String {
        switch self {
        case .pota: "POTA"
        case .sota: "SOTA"
        }
    }

    var icon: String {
        switch self {
        case .pota: "tree"
        case .sota: "mountain.2"
        }
    }
}
```

Empty set = casual session. No explicit "casual" case needed.

### LoggingSession Changes

- New field: `programsRawValue: String` (JSON-encoded `[String]`, e.g. `["pota","sota"]`)
- Computed property: `var programs: Set<OperatingProgram>` (get/set via JSON encode/decode)
- Convenience: `var isPOTA: Bool`, `var isSOTA: Bool`, `var isCasual: Bool`
- Existing `parkReference` and `sotaReference` remain as-is (independent of each other)
- **Migration:** Lazy migration from `activationTypeRawValue` on first read — `"pota"` -> `["pota"]`, `"sota"` -> `["sota"]`, `"casual"` -> `[]`. Old field stays for backward compat but is no longer source of truth.

### ActiveStation.Source

Add SOTA case:

```swift
enum Source: Sendable {
    case pota(park: String)
    case sota(summit: String, points: Int)
    case rbn(snr: Int)
}
```

### SOTASpot

New data model for SOTAwatch spots:

```swift
struct SOTASpot: Codable, Sendable, Identifiable {
    let id: Int
    let activatorCallsign: String
    let summitCode: String       // "W4C/CM-001"
    let summitName: String
    let frequency: String        // "14.062" (string from API)
    let mode: String             // "CW", "SSB", "FM"
    let comments: String?
    let points: Int
    let timeStamp: String        // ISO date from API

    var frequencyMHz: Double? { ... }
    var parsedTimestamp: Date? { ... }
}
```

## Session Start UI

### Toggle Chips (Replaces Segmented Picker)

The activation section changes from a 3-segment picker (`Casual | POTA | SOTA`) to independent toggle chips:

```
┌─────────────────────────────────────┐
│ Programs                            │
│                                     │
│  [ 🌲 POTA ]  [ ⛰ SOTA ]          │  ← Toggle chips (pill buttons)
│                                     │
│  Neither selected = casual session  │  ← Footer hint
│                                     │
│  ┌─ Parks ────────────────────────┐ │  ← Appears when POTA toggled on
│  │ [K-1234, K-5678    ] [search] │ │
│  │ ☐ This is a rove              │ │
│  └────────────────────────────────┘ │
│                                     │
│  ┌─ Summit ───────────────────────┐ │  ← Appears when SOTA toggled on
│  │ [W4C/CM-001         ] [search]│ │
│  │  Mount Mitchell  6,684 ft      │ │
│  └────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**Toggle chip style:** HIG-compliant bordered capsule buttons. Filled when active (tinted background + checkmark), outlined when inactive. Similar to existing `SpotFilterBar` chips.

**Validation:**
- POTA toggled on -> park reference required
- SOTA toggled on -> summit reference required
- Neither -> always valid (casual)

**Default persistence:** `@AppStorage` saves the program set (JSON), park ref, and summit ref separately.

## HUNT Command + Unified Spots Panel

### Logger Command Changes

- Rename `.pota` case to `.hunt`
- Parse: `HUNT` is primary command. `POTA` and `SPOTS` kept as aliases.
- Icon: `binoculars` (or `binoculars.fill`)
- Help text: `HUNT - Show activator spots (POTA + SOTA)`

### Unified Spots Panel (Phone)

```
┌────────────────────────────────────┐
│ Activator Spots              [✕]   │
│ ┌──────────────────────────────┐   │
│ │ [All] [POTA] [SOTA] [RBN]   │   │  ← Source filter chips
│ │ [Band ▾] [Mode ▾]           │   │  ← Existing filters
│ └──────────────────────────────┘   │
│                                    │
│ 🌲 W4DOG   14.062 CW   K-1234    │  ← POTA spot: tree badge
│    Blackwater Falls SP   2m ago    │
│                                    │
│ ⛰ N5RZ    7.030  CW   W4C/CM-001 │  ← SOTA spot: mountain badge
│    Mt Mitchell  8pts     5m ago    │
└────────────────────────────────────┘
```

**Spot row details:**
- Left badge: program icon (tree for POTA, mountain for SOTA, both for overlap)
- Callsign, frequency, mode prominently displayed
- Reference (park code or summit code) + human name
- SOTA spots show points value
- Age coloring: green (<2m), blue (<10m), orange (<30m), gray (>30m)
- Tap behavior: fills logger with callsign, frequency, mode, and their park/summit reference

### iPad Sidebar

`SidebarTab.pota` renamed to `.hunt`. Shows unified spot list.

### Hunter Activity Log

`ActivityLogSpotsList` extends to include SOTA spots. `SpotFilterSheet` gets SOTA source option.

## SOTAwatch API Integration

### SOTAClient

New actor service: `SOTAClient` (matches `POTAClient` pattern).

**Endpoint:** `https://api2.sota.org.uk/api/spots/{count}/{associationFilter}`

**Polling:** 60-second interval when spots panel is visible, matching POTA spot polling cadence.

### SpotMonitoringService Integration

1. Fetch SOTA spots from `SOTAClient`
2. Convert `SOTASpot` -> `ActiveStation` with `.sota(summit:points:)` source
3. Merge into unified spot list, sorted by timestamp
4. Overlap detection: if POTA + SOTA spots share callsign + similar frequency + similar time, mark as dual-program

## File Changes

### New Files

| File | Purpose |
|------|---------|
| `Services/SOTA/SOTAClient.swift` | SOTAwatch spots API client |
| `Services/SOTA/SOTAClient+Spots.swift` | Spot fetching and parsing |
| `Models/SOTASpot.swift` | SOTA spot data model |
| `Models/OperatingProgram.swift` | Program enum replacing ActivationType |

### Modified Files

| File | Change |
|------|--------|
| `LoggingSession.swift` | Add `programsRawValue`, computed `programs`, convenience properties |
| `LoggerCommand.swift` | Rename `.pota` -> `.hunt`, update parsing + aliases |
| `LoggerCommand+Suggestions.swift` | Update suggestion for HUNT command |
| `SessionStartSheet.swift` | Store/restore program set defaults |
| `SessionStartSheet+Sections.swift` | Toggle chips replacing segmented picker |
| `SessionStartHelperViews.swift` | Update `ActivationSectionView` + `SessionStartValidation` |
| `ActiveStation.swift` | Add `.sota` source case, `fromSOTA()` factory |
| `SpotMonitoringService.swift` | Integrate SOTA spot polling |
| `SpotsService.swift` | Merge SOTA into combined feed |
| `LoggerSpotsSidebarView.swift` | Rename POTA tab to Hunt |
| `SpotSelection.swift` | Rename `SidebarTab.pota` -> `.hunt`, add `.sota` to `SpotSelection` |
| `POTASpotsView.swift` | Extend to show SOTA spots in unified list |
| `POTASpotRow.swift` | Add SOTA badge support |
| `ActivityLogSpotsList.swift` | Include SOTA spots in hunter feed |
| `ActivityLogSpotRow.swift` | Add SOTA badge support |
| `SpotFilterSheet.swift` | Add SOTA source filter |
| `SpotFilters.swift` | Add SOTA to source enum |
| Various files with `activationType == .pota` | Convert to `programs.contains(.pota)` |
| Various files with `activationType == .sota` | Convert to `programs.contains(.sota)` |
| `iPadCommandStrip.swift` | Update POTA button to HUNT |
| `LoggerView+Commands.swift` | Handle `.hunt` command |
| `LoggerKeyboardAccessory.swift` | Update command button |
| `CommandRowSettingsView.swift` | Update command options |
