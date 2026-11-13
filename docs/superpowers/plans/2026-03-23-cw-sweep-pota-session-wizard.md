# CW Sweep POTA Session Wizard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a POTA-focused inline session setup wizard in CW Sweep's ActivatorLayout with a regulated band map, rove planner, and spotting commands.

**Architecture:** The wizard replaces ActivatorLayout's empty state with a two-phase inline panel. Phase 1 (essentials) shows park search, operators, and band map. Phase 2 (expandable) adds equipment, rove planner, and notes. Post-start commands handle spotting and return-to-frequency.

**Tech Stack:** SwiftUI (macOS), SwiftData, MapKit, Canvas, CarrierWaveCore, CarrierWaveData

**Spec:** `docs/superpowers/specs/2026-03-23-cw-sweep-pota-session-wizard-design.md`

---

## File Map

### New Files (CW Sweep)

| File | Responsibility |
|------|---------------|
| `CWSweep/Views/Activation/POTASetupView.swift` | Top-level wizard view (essentials row + band map + expandable section) |
| `CWSweep/Views/Activation/POTASetupView+Essentials.swift` | Park search, callsign display, operator chips, start button |
| `CWSweep/Views/Activation/POTASetupView+FullSetup.swift` | Equipment, power, grid, attendees, notes (left column) |
| `CWSweep/Views/Activation/POTASetupView+Actions.swift` | Start session logic, validation, defaults |
| `CWSweep/Views/Activation/RegulatedBandMapView.swift` | Full-band overview strip + zoomed view with privilege enforcement |
| `CWSweep/Views/Activation/RegulatedBandMapView+Canvas.swift` | Canvas drawing: segments, spots, VFO cursor, hit testing |
| `CWSweep/Views/Activation/RovePlannerView.swift` | Map + ordered stop list, add/remove/reorder stops |
| `CWSweep/Views/Activation/ParkSearchField.swift` | macOS-adapted park search (typeahead, recent parks) |
| `CWSweep/Views/Activation/OperatorChipsView.swift` | Operator chip list with add/remove, auto-commit on comma/space |
| `CWSweep/Views/Settings/POTASettingsTab.swift` | License class, auto-spot toggles, re-spot interval, comment template |
| `CWSweep/Services/Spots/POTASpotService.swift` | Self-spot posting, re-spot timer, comment token substitution |

### Modified Files

| File | Change |
|------|--------|
| `CWSweep/Views/Roles/ActivatorLayout.swift` | Replace empty state with `POTASetupView`; show logger when session active |
| `CWSweep/Views/Roles/ActivatorLayout.swift` | Add activation frequency/mode storage for return-to-freq command |
| `CWSweep/Commands/CWSweepCommands.swift` | Add POTA menu: Return to My Frequency (⌘⇧R), Edit Spot Comment (⌘⇧C) |
| `CWSweep/Utilities/FocusedValues.swift` | Add `ReturnToFrequencyAction`, `EditSpotCommentAction` keys |
| `CWSweep/Views/CommandPalette/RadioPaletteActions.swift` | Handle `SPOT [comment]` text command |
| `CWSweep/Views/Settings/SettingsView.swift` | Add POTA settings tab |
| `CWSweep/Views/Spots/SpotListView.swift` (if exists) | P2P badge highlighting for POTA activator spots |

### Shared Package Changes

| File | Change |
|------|--------|
| `CarrierWaveCore/Sources/CarrierWaveCore/BandPlanPrivileges.swift` (new) | US operator class sub-band boundaries per band (Extra/General/Technician) |

### Dependencies That Need Moving

| Current Location | Target | Reason |
|-----------------|--------|--------|
| `CarrierWave/Models/BandPlan.swift` | `CarrierWaveCore/Sources/CarrierWaveCore/BandPlan.swift` | CW Sweep needs band plan data; currently iOS-only |
| `CarrierWave/Services/POTAClient+Spot.swift` | `CarrierWaveData/Sources/CarrierWaveData/Services/POTASpotService.swift` or keep iOS-only and reimplement in CWSweep | Self-spot API; depends on `POTAAuthProvider` protocol (already in CarrierWaveData) |

---

## Task 1: Move BandPlan to CarrierWaveCore

BandPlan must be in the shared package for CW Sweep to use it.

**Files:**
- Move: `CarrierWave/Models/BandPlan.swift` → `CarrierWaveCore/Sources/CarrierWaveCore/BandPlan.swift`
- Modify: `CarrierWave/` files that import BandPlan (update imports if needed)
- Modify: `CarrierWaveCore/Sources/CarrierWaveCore/` Package.swift if needed

- [ ] **Step 1: Check BandPlan dependencies**

Read `CarrierWave/Models/BandPlan.swift` fully to identify any iOS-only imports (UIKit, CarrierWaveData, SwiftData). If it only depends on Foundation and CarrierWaveCore types, it can move directly. If it has iOS dependencies, extract the pure data portion.

- [ ] **Step 2: Copy BandPlan to CarrierWaveCore**

Copy `CarrierWave/Models/BandPlan.swift` to `CarrierWaveCore/Sources/CarrierWaveCore/BandPlan.swift`. Change access control to `public` on all types and properties that CW Sweep needs (at minimum: `BandSegment`, `FrequencyActivity`, `BandPlan` static arrays). Remove any iOS-only code.

- [ ] **Step 3: Update iOS app to import from CarrierWaveCore**

The iOS app already imports CarrierWaveCore. Remove the local `BandPlan.swift` from the iOS target and verify the iOS app's references still compile — all callers should see the type through CarrierWaveCore.

- [ ] **Step 4: Verify both targets build**

Build CWSweep:
```bash
cd CWSweep && swift build
```
Build iOS (if local Xcode available):
```bash
xc build
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: move BandPlan to CarrierWaveCore for shared access"
```

---

## Task 2: Add Operator Class Privilege Boundaries

New data file defining which sub-bands each license class can use per band.

**Files:**
- Create: `CarrierWaveCore/Sources/CarrierWaveCore/BandPlanPrivileges.swift`

- [ ] **Step 1: Create BandPlanPrivileges data**

```swift
import Foundation

/// US amateur operator license classes
public enum LicenseClass: String, CaseIterable, Codable, Sendable {
    case technician = "Technician"
    case general = "General"
    case extra = "Extra"
}

/// A frequency privilege range for a specific license class
public struct PrivilegeSegment: Sendable {
    public let band: String
    public let startMHz: Double
    public let endMHz: Double
    public let minimumClass: LicenseClass
    public let modes: Set<String> // "CW", "Phone", "Digital", "All"
}

/// US amateur radio operator class sub-band privileges
public enum BandPlanPrivileges {
    /// All privilege segments by band, sorted by frequency
    public static let segments: [PrivilegeSegment] = [
        // 160m — General and Extra: CW/Digital 1.800-2.000
        PrivilegeSegment(band: "160m", startMHz: 1.800, endMHz: 2.000, minimumClass: .general, modes: ["CW", "Digital"]),

        // 80m — Technician CW 3.525-3.600, General CW/Digital 3.525-3.600, Extra CW/Digital 3.500-3.525
        PrivilegeSegment(band: "80m", startMHz: 3.500, endMHz: 3.525, minimumClass: .extra, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "80m", startMHz: 3.525, endMHz: 3.600, minimumClass: .technician, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "80m", startMHz: 3.600, endMHz: 3.700, minimumClass: .extra, modes: ["Phone"]),
        PrivilegeSegment(band: "80m", startMHz: 3.700, endMHz: 3.800, minimumClass: .general, modes: ["Phone"]),
        PrivilegeSegment(band: "80m", startMHz: 3.800, endMHz: 4.000, minimumClass: .general, modes: ["Phone"]),

        // 40m — Technician CW 7.025-7.125, Extra CW/Digital 7.000-7.025
        PrivilegeSegment(band: "40m", startMHz: 7.000, endMHz: 7.025, minimumClass: .extra, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "40m", startMHz: 7.025, endMHz: 7.125, minimumClass: .technician, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "40m", startMHz: 7.125, endMHz: 7.175, minimumClass: .extra, modes: ["Phone"]),
        PrivilegeSegment(band: "40m", startMHz: 7.175, endMHz: 7.300, minimumClass: .general, modes: ["Phone"]),

        // 30m — General and Extra only, CW/Digital
        PrivilegeSegment(band: "30m", startMHz: 10.100, endMHz: 10.150, minimumClass: .general, modes: ["CW", "Digital"]),

        // 20m
        PrivilegeSegment(band: "20m", startMHz: 14.000, endMHz: 14.025, minimumClass: .extra, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "20m", startMHz: 14.025, endMHz: 14.150, minimumClass: .general, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "20m", startMHz: 14.150, endMHz: 14.175, minimumClass: .extra, modes: ["Phone"]),
        PrivilegeSegment(band: "20m", startMHz: 14.175, endMHz: 14.350, minimumClass: .general, modes: ["Phone"]),

        // 17m — General+ all modes
        PrivilegeSegment(band: "17m", startMHz: 18.068, endMHz: 18.110, minimumClass: .general, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "17m", startMHz: 18.110, endMHz: 18.168, minimumClass: .general, modes: ["Phone"]),

        // 15m — Technician CW 21.025-21.200, Extra CW/Digital 21.000-21.025
        PrivilegeSegment(band: "15m", startMHz: 21.000, endMHz: 21.025, minimumClass: .extra, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "15m", startMHz: 21.025, endMHz: 21.200, minimumClass: .technician, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "15m", startMHz: 21.200, endMHz: 21.225, minimumClass: .extra, modes: ["Phone"]),
        PrivilegeSegment(band: "15m", startMHz: 21.225, endMHz: 21.450, minimumClass: .general, modes: ["Phone"]),

        // 12m — General+ all modes
        PrivilegeSegment(band: "12m", startMHz: 24.890, endMHz: 24.930, minimumClass: .general, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "12m", startMHz: 24.930, endMHz: 24.990, minimumClass: .general, modes: ["Phone"]),

        // 10m — Technician CW/Digital 28.000-28.300, Technician Phone 28.300-28.500
        PrivilegeSegment(band: "10m", startMHz: 28.000, endMHz: 28.300, minimumClass: .technician, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "10m", startMHz: 28.300, endMHz: 28.500, minimumClass: .technician, modes: ["Phone"]),
        PrivilegeSegment(band: "10m", startMHz: 28.500, endMHz: 29.700, minimumClass: .technician, modes: ["Phone"]),

        // 6m
        PrivilegeSegment(band: "6m", startMHz: 50.000, endMHz: 50.100, minimumClass: .technician, modes: ["CW", "Digital"]),
        PrivilegeSegment(band: "6m", startMHz: 50.100, endMHz: 54.000, minimumClass: .technician, modes: ["All"]),
    ]

    /// Check if a frequency/mode combination is permitted for a given license class
    public static func isPermitted(
        frequencyMHz: Double,
        mode: String,
        licenseClass: LicenseClass
    ) -> Bool {
        let classOrder: [LicenseClass] = [.technician, .general, .extra]
        guard let userIdx = classOrder.firstIndex(of: licenseClass) else {
            return false
        }
        return segments.contains { seg in
            frequencyMHz >= seg.startMHz
                && frequencyMHz <= seg.endMHz
                && (seg.modes.contains(mode) || seg.modes.contains("All"))
                && userIdx >= (classOrder.firstIndex(of: seg.minimumClass) ?? 0)
        }
    }

    /// Get segments for a specific band
    public static func segments(for band: String) -> [PrivilegeSegment] {
        segments.filter { $0.band == band }
    }
}
```

- [ ] **Step 2: Build CarrierWaveCore to verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 3: Commit**

```bash
git add CarrierWaveCore/Sources/CarrierWaveCore/BandPlanPrivileges.swift
git commit -m "feat: add US operator class band privilege data to CarrierWaveCore"
```

---

## Task 3: POTA Settings Tab

Add the POTA settings to CW Sweep before building the wizard, since the wizard reads these settings.

**Files:**
- Create: `CWSweep/CWSweep/Views/Settings/POTASettingsTab.swift`
- Modify: `CWSweep/CWSweep/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Create POTASettingsTab**

```swift
import SwiftUI

struct POTASettingsTab: View {
    @AppStorage("licenseClass") var licenseClass = "General"
    @AppStorage("potaAutoSpotOnStart") var autoSpotOnStart = false
    @AppStorage("potaReSpotEnabled") var reSpotEnabled = false
    @AppStorage("potaReSpotIntervalMinutes") var reSpotInterval = 30
    @AppStorage("potaAutoSpotOnRoveChange") var autoSpotOnRoveChange = false
    @AppStorage("potaSpotCommentTemplate") var spotCommentTemplate = "[MODE] [BAND]"

    var body: some View {
        Form {
            Section("License Class") {
                Picker("License Class", selection: $licenseClass) {
                    Text("Technician").tag("Technician")
                    Text("General").tag("General")
                    Text("Extra").tag("Extra")
                }
                Text("Used to show operator privilege boundaries on the band map")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Self-Spotting") {
                Toggle("Auto self-spot on session start", isOn: $autoSpotOnStart)
                Toggle("Auto self-spot on rove stop change", isOn: $autoSpotOnRoveChange)

                Toggle("Periodic re-spot", isOn: $reSpotEnabled)
                if reSpotEnabled {
                    Picker("Re-spot interval", selection: $reSpotInterval) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("45 minutes").tag(45)
                        Text("60 minutes").tag(60)
                    }
                }

                TextField("Spot comment template", text: $spotCommentTemplate)
                Text("Tokens: [MODE], [BAND], [PARK], [CALL]")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Add tab to SettingsView**

In `CWSweep/CWSweep/Views/Settings/SettingsView.swift`, add after the `DataSettingsTab`:

```swift
POTASettingsTab()
    .tabItem { Label("POTA", systemImage: "tree") }
```

- [ ] **Step 3: Build and verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 4: Commit**

```bash
git add CWSweep/CWSweep/Views/Settings/POTASettingsTab.swift CWSweep/CWSweep/Views/Settings/SettingsView.swift
git commit -m "feat: add POTA settings tab (license class, auto-spot toggles, comment template)"
```

---

## Task 4: Park Search Field

macOS-adapted park search with typeahead. This is a prerequisite for the wizard's essentials row.

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/ParkSearchField.swift`

- [ ] **Step 1: Study the iOS ParkEntryField**

Read `CarrierWave/Views/Logger/ParkEntryField.swift` to understand the POTA park search API endpoint, debouncing, and result model. The search hits `https://api.pota.app/park/autocomplete?query=`.

- [ ] **Step 2: Create ParkSearchField for macOS**

Build a macOS text field with:
- Typeahead suggestions in a dropdown (NSPopover or overlay)
- Debounced search (300ms) hitting the POTA autocomplete API
- Shows park name, reference, grid, state
- Recent parks section (stored in `@AppStorage`)
- `onParkSelected` callback returning park reference and grid

Reference `CWSweep/CWSweep/Services/Spots/POTASpotsClient.swift` for the existing POTA API pattern. The autocomplete endpoint is public/unauthenticated.

- [ ] **Step 3: Build and verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 4: Commit**

```bash
git add CWSweep/CWSweep/Views/Activation/ParkSearchField.swift
git commit -m "feat: add macOS park search field with typeahead autocomplete"
```

---

## Task 5: Operator Chips View

Reusable operator chip list with add/remove.

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/OperatorChipsView.swift`

- [ ] **Step 1: Create OperatorChipsView**

A FlowLayout (or `HStack` with `wrappedLayout`) of callsign chips. The user's own callsign is always shown first and not removable. Additional operators can be added via a text field that auto-commits on comma, space, or Enter. Each chip has an `×` button to remove.

Reference `CarrierWave/Views/Logger/SessionStartSheet+Equipment.swift:261-332` for the iOS operator chips pattern.

Input: `@Binding var operators: [String]`, `myCallsign: String`

- [ ] **Step 2: Build and verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 3: Commit**

```bash
git add CWSweep/CWSweep/Views/Activation/OperatorChipsView.swift
git commit -m "feat: add operator chips view with auto-commit input"
```

---

## Task 6: Regulated Band Map — Overview Strip

The full-band overview showing mode segments and operator class boundaries.

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/RegulatedBandMapView.swift`
- Create: `CWSweep/CWSweep/Views/Activation/RegulatedBandMapView+Canvas.swift`

- [ ] **Step 1: Study existing BandMapView**

Read `CWSweep/CWSweep/Views/Spots/BandMapView.swift` fully to understand the Canvas rendering pattern, `BandEdges` x-position mapping, and `SpotAggregator` integration. The new view will follow the same patterns but add privilege segments and a two-tier layout.

- [ ] **Step 2: Create RegulatedBandMapView (structure)**

In `RegulatedBandMapView.swift`: the outer view with band pill selector, full-band overview strip, and zoomed view. Takes `@Environment(SpotAggregator.self)` and `@Environment(RadioManager.self)`. Reads `@AppStorage("licenseClass")` for privilege enforcement.

State: `selectedBandId`, `zoomCenter` (MHz), `zoomScale`, `hoveredSpot`.

- [ ] **Step 3: Create Canvas drawing (RegulatedBandMapView+Canvas.swift)**

Drawing pipeline:
1. `drawOverviewStrip()` — full band with mode segment fills (purple CW/Digital, green Phone), hatched overlay for Extra-only zones (using diagonal line pattern), red dashed boundary lines between class regions. Uses `BandPlanPrivileges.segments(for:)`.
2. `drawZoomedView()` — portion of band centered on `zoomCenter`. Draws spots from `SpotAggregator` with source-specific colors (amber RBN/cluster, green POTA, blue SOTA/WWFF). VFO cursor as red vertical line. Clear-zone indicator: dashed green border showing ±1 kHz clear space around VFO (check if any spots fall within the window; if clear, show green "clear ±1 kHz" label).
3. `drawFrequencyAxis()` — tick marks and labels.
4. Hit testing: store `hitRects` array like existing BandMapView. On click, if frequency is permitted for user's license class, call `radioManager.tuneToSpot()`. If restricted, show a transient "Extra only" warning.

Interactions: `onTapGesture` for click-to-tune, `MagnifyGesture` or scroll for zoom, `DragGesture` for pan.

- [ ] **Step 4: Build and verify the Canvas renders**

```bash
cd CWSweep && swift build
```

- [ ] **Step 5: Commit**

```bash
git add CWSweep/CWSweep/Views/Activation/RegulatedBandMapView.swift CWSweep/CWSweep/Views/Activation/RegulatedBandMapView+Canvas.swift
git commit -m "feat: add regulated band map with privilege boundaries and spot overlay"
```

---

## Task 7: Rove Planner View

Map-based rove stop planner with ordered list.

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/RovePlannerView.swift`

- [ ] **Step 1: Create RovePlannerView**

Two sections:
1. MapKit `Map` view with `Annotation` markers for each stop (numbered, color-coded). `MapPolyline` for dashed route lines between stops.
2. Below the map: ordered stop list. Each row shows stop number, park reference, park name, grid, distance from previous (computed via `MaidenheadConverter.haversineDistance` from CarrierWaveCore). Drag-to-reorder using `onMove`. "Add stop" row with embedded `ParkSearchField`.

Input: `@Binding var isRove: Bool`, `@Binding var stops: [RoveStopEntry]` where `RoveStopEntry` is a local struct (reference, name, grid, latitude, longitude).

When `isRove` is false, shows the single selected park on the map (read-only).

Reference `CarrierWaveCore/Sources/CarrierWaveCore/MaidenheadConverter.swift` for grid-to-coordinate conversion and distance calculation.

- [ ] **Step 2: Build and verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 3: Commit**

```bash
git add CWSweep/CWSweep/Views/Activation/RovePlannerView.swift
git commit -m "feat: add map-based rove planner with stop ordering and distance"
```

---

## Task 8: POTASetupView — Main Wizard

Assemble the wizard from the components built in Tasks 4-7.

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/POTASetupView.swift`
- Create: `CWSweep/CWSweep/Views/Activation/POTASetupView+Essentials.swift`
- Create: `CWSweep/CWSweep/Views/Activation/POTASetupView+FullSetup.swift`
- Create: `CWSweep/CWSweep/Views/Activation/POTASetupView+Actions.swift`

- [ ] **Step 1: Create POTASetupView (shell)**

The top-level view. Layout:
```
VStack(spacing: 0) {
    topBar          // "Start POTA Activation" + radio status
    essentialsRow   // Park, callsign, operators, Start button
    Divider()
    bandMap         // RegulatedBandMapView
    fullSetupDisclosure  // DisclosureGroup with ⌘⇧S shortcut
}
```

State: `parkReference`, `parkName`, `parkGrid`, `operators: [String]`, `callsignPrefix`, `selectedSuffix`, `customSuffix`, `isRove`, `roveStops`, `selectedAntenna`, `selectedKey`, `selectedMic`, `powerText`, `myGrid`, `extraEquipment`, `attendees`, `sessionNotes`, `showFullSetup`.

Environment: `@Environment(RadioManager.self)`, `@Environment(SpotAggregator.self)`, `@Environment(\.modelContext)`.

- [ ] **Step 2: Create POTASetupView+Essentials.swift**

The essentials row: `HStack` with `ParkSearchField`, callsign display (monospaced, with expandable prefix/suffix via popover), `OperatorChipsView`, and Start button. Start button disabled with reason text until park is selected.

- [ ] **Step 3: Create POTASetupView+FullSetup.swift**

The expandable section: `DisclosureGroup("Full Setup", isExpanded: $showFullSetup)`. Two-column `HSplitView`:
- Left: Equipment section (radio auto-detected from `radioManager.radioName`, antenna/key/mic pickers using the existing equipment list pattern from iOS — `@AppStorage` for saved equipment), power field, grid (auto-filled from park, editable), attendees, notes.
- Right: `RovePlannerView` bound to `isRove` and `roveStops`.

- [ ] **Step 4: Create POTASetupView+Actions.swift**

`startSession()` method:
1. Create `LoggingSession` with all wizard fields mapped per the spec's data model table.
2. Insert into `modelContext`.
3. Tune radio: `radioManager.tuneToSpot(frequencyMHz:mode:)` using current VFO or band-map-selected frequency.
4. Store activation frequency/mode for return-to-freq command (publish via `FocusedValues`).
5. Ensure spots are running: check `spotAggregator.isPolling`, start if not.
6. Auto-spot on start: if `@AppStorage("potaAutoSpotOnStart")` is true, call `POTASpotService.postSpot()` with the session's park reference, frequency, mode, and resolved comment template. This depends on Task 10 (POTASpotService), so wire it with an optional reference — if the service isn't available yet, this step is a no-op that gets completed in Task 10.
7. Start re-spot timer: if `@AppStorage("potaReSpotEnabled")` is true, call `POTASpotService.startReSpotTimer(intervalMinutes:)`.

Validation logic: `canStart` computed property — requires park reference, callsign ≥ 3 chars. `startDisabledReason` for the label text.

`saveDefaults()` to persist current choices to `@AppStorage`.

- [ ] **Step 5: Build and verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 6: Commit**

```bash
git add CWSweep/CWSweep/Views/Activation/POTASetupView*.swift
git commit -m "feat: add POTASetupView wizard with essentials, full setup, and start logic"
```

---

## Task 9: Wire Wizard into ActivatorLayout

Replace the empty state with the wizard.

**Files:**
- Modify: `CWSweep/CWSweep/Views/Roles/ActivatorLayout.swift`

- [ ] **Step 1: Modify ActivatorLayout**

Currently, `ActivatorLayout` always shows the logger/spots layout. Change it to:
- When `activeSession` is `nil` (no active POTA session), show `POTASetupView` in the content area.
- When `activeSession` exists, show the existing `ActivationHeader` + `ParsedEntryView` + `QSOLogTableView` + `SpotListView`.

The `ActivationHeader.loadActiveSession()` pattern already fetches the active session. Lift this state to `ActivatorLayout` so the view can switch between setup and operating modes.

- [ ] **Step 2: Add activation frequency storage**

Add `@State private var activationFrequencyMHz: Double?` and `@State private var activationMode: String?` to `ActivatorLayout`. Set these when a session starts (from `POTASetupView`'s start action). Publish via `focusedSceneValue` for the return-to-freq command.

- [ ] **Step 3: Build and verify the view switch works**

```bash
cd CWSweep && swift build
```

- [ ] **Step 4: Commit**

```bash
git add CWSweep/CWSweep/Views/Roles/ActivatorLayout.swift
git commit -m "feat: wire POTASetupView into ActivatorLayout empty state"
```

---

## Task 10: POTA Spotting Service

Self-spot posting with re-spot timer and comment token substitution.

**Files:**
- Create: `CWSweep/CWSweep/Services/Spots/POTASpotService.swift`

- [ ] **Step 1: Study iOS spotting implementation**

Read `CarrierWave/Services/POTAClient+Spot.swift` (already reviewed — uses `POTAAuthProvider` and hits `POST /spot`). Read `CarrierWave/Services/LoggingSessionManager+Spotting.swift` for timer logic.

- [ ] **Step 2: Create POTASpotService**

`@MainActor @Observable` class. Responsibilities:
- `postSpot(callsign:reference:frequencyKHz:mode:comment:)` — POST to POTA spot API. Requires POTA authentication (check if CWSweep has `POTAAuthProvider` — likely needs a macOS implementation using `ASWebAuthenticationSession`).
- `startReSpotTimer(intervalMinutes:)` — repeating `Task.sleep` loop that calls `postSpot`.
- `stopReSpotTimer()` — cancel the timer task.
- `resolveComment(template:mode:band:park:callsign:)` — token substitution `[MODE]`, `[BAND]`, `[PARK]`, `[CALL]`.

**Note:** If POTA auth doesn't exist in CWSweep yet, create a stub that reads credentials from Keychain (matching the iOS pattern). Full OAuth can be a follow-up. The service should gracefully handle `notAuthenticated` and surface it to the user.

- [ ] **Step 3: Add QSY auto-update behavior**

The service should observe `RadioManager.frequency` and `RadioManager.mode`. When they change during an active session:
- Auto-update the spot comment's `[BAND]` and `[MODE]` tokens while preserving custom text.
- Store the resolved comment so the next manual or auto spot uses the updated values.
- Use `withObservationTracking` or a `Task` polling `RadioManager` to detect changes (RadioManager is `@Observable`).

- [ ] **Step 4: Add rove stop change spotting**

When the active session's park reference changes (rove stop advance):
- If `@AppStorage("potaAutoSpotOnRoveChange")` is true, post a new self-spot with the new park reference.
- Reset the re-spot timer so the interval restarts from the park change.
- The rove stop advance triggers from `RovePlannerView` or the session manager — wire a callback.

- [ ] **Step 5: Add re-spot timer countdown to ActivationHeader**

Modify `CWSweep/CWSweep/Views/Roles/ActivatorLayout.swift` (the `ActivationHeader` section):
- When re-spot timer is active, show a subtle countdown label (e.g., "next spot in 12:34") in the header bar near the QSO count.
- Use `POTASpotService.nextSpotDate` published property and a 1-second timer to update the display.
- Style: small monospaced text, secondary color, with a subtle antenna icon.

- [ ] **Step 6: Build and verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 7: Commit**

```bash
git add CWSweep/CWSweep/Services/Spots/POTASpotService.swift CWSweep/CWSweep/Views/Roles/ActivatorLayout.swift
git commit -m "feat: add POTA spot service with re-spot timer, QSY auto-update, and header countdown"
```

---

## Task 11: Commands — Return to Frequency, Edit Spot Comment, SPOT

Wire up the three new commands.

**Files:**
- Modify: `CWSweep/CWSweep/Utilities/FocusedValues.swift`
- Modify: `CWSweep/CWSweep/Commands/CWSweepCommands.swift`
- Modify: `CWSweep/CWSweep/Views/CommandPalette/RadioPaletteActions.swift`

- [ ] **Step 1: Add FocusedValue keys**

In `FocusedValues.swift`, add:
- `ReturnToFrequencyAction` + `ReturnToFrequencyKey`
- `EditSpotCommentAction` + `EditSpotCommentKey`
- `ActivationFrequencyKey` (value: `(Double, String)?` — frequency MHz and mode)

Follow the exact pattern of existing keys (e.g., `FocusEntryFieldAction`).

Add to `FocusedValues` extension:
```swift
var returnToFrequency: ReturnToFrequencyAction? { ... }
var editSpotComment: EditSpotCommentAction? { ... }
var activationFrequency: (Double, String)? { ... }
```

- [ ] **Step 2: Add menu commands**

In `CWSweepCommands.swift`, add a new `CommandMenu("POTA")`:
```swift
CommandMenu("POTA") {
    Button("Return to My Frequency") {
        returnToFrequency?()
    }
    .keyboardShortcut("r", modifiers: [.command, .shift])
    .disabled(activationFrequency == nil)

    Button("Edit Spot Comment") {
        editSpotComment?()
    }
    .keyboardShortcut("c", modifiers: [.command, .shift])
}
```

**Note:** `⌘⇧R` conflicts with the existing "Connect Radio..." shortcut in the Radio menu. Change the Radio connect shortcut to something else (e.g., `⌘⌥R`) since Return to My Frequency is more frequently used during operation.

- [ ] **Step 3: Add SPOT command to command palette**

In `RadioPaletteActions.swift`, in `executeCommand()`, add a check before the `RadioCommandParser.parse` call:

```swift
let trimmed = searchText.trimmingCharacters(in: .whitespaces)
if trimmed.uppercased().hasPrefix("SPOT") {
    let comment = trimmed.count > 4
        ? String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        : nil
    Task { await spotService?.postSpot(comment: comment) }
    dismiss()
    return
}
```

The `spotService` needs to be accessible — either via environment or FocusedValues.

- [ ] **Step 4: Wire actions in ActivatorLayout/WorkspaceView**

In `ActivatorLayout` (or wherever FocusedValues are published), publish the return-to-frequency action:
```swift
.focusedSceneValue(\.returnToFrequency, ReturnToFrequencyAction {
    guard let freq = activationFrequencyMHz, let mode = activationMode else { return }
    Task { try? await radioManager.tuneToSpot(frequencyMHz: freq, mode: mode) }
})
```

- [ ] **Step 5: Build and verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 6: Commit**

```bash
git add CWSweep/CWSweep/Utilities/FocusedValues.swift CWSweep/CWSweep/Commands/CWSweepCommands.swift CWSweep/CWSweep/Views/CommandPalette/RadioPaletteActions.swift
git commit -m "feat: add POTA commands (return to freq, edit spot comment, SPOT)"
```

---

## Task 12: P2P Spot Highlighting

Show P2P badge on POTA spots when the user is also activating.

**Files:**
- Modify: `CWSweep/CWSweep/Views/Spots/SpotListView.swift` (or equivalent spot list view in the Activator layout)

- [ ] **Step 1: Identify the spot list view used in ActivatorLayout**

Check `CWSweep/CWSweep/Views/Roles/ActivatorLayout.swift` — it references `SpotListView()`. Read that file to understand the spot row rendering.

- [ ] **Step 2: Add P2P detection**

When there's an active POTA session, check each POTA spot: if the spotted activator is at a POTA park and the user is also a POTA activator, it's a P2P opportunity. Show a "P2P" badge (green capsule) with the park reference and distance (via `MaidenheadConverter.haversineDistance`).

- [ ] **Step 3: Add double-click to tune**

On the spot row, add `.onTapGesture(count: 2)` that calls `radioManager.tuneToSpot()` with the spot's frequency and mode.

- [ ] **Step 4: Build and verify**

```bash
cd CWSweep && swift build
```

- [ ] **Step 5: Commit**

```bash
git add CWSweep/CWSweep/Views/Spots/SpotListView.swift
git commit -m "feat: add P2P badge and double-click-to-tune on POTA spots"
```

---

## Task 13: Update FILE_INDEX.md and CHANGELOG.md

**Files:**
- Modify: `docs/FILE_INDEX.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add new CWSweep files to FILE_INDEX.md**

Add entries for all new files under the CWSweep section:
- `Views/Activation/POTASetupView.swift` — POTA session setup wizard (top-level)
- `Views/Activation/POTASetupView+Essentials.swift` — Park search, callsign, operators, start button
- `Views/Activation/POTASetupView+FullSetup.swift` — Equipment, power, rove planner, notes
- `Views/Activation/POTASetupView+Actions.swift` — Session start logic and validation
- `Views/Activation/RegulatedBandMapView.swift` — Band map with privilege boundaries
- `Views/Activation/RegulatedBandMapView+Canvas.swift` — Canvas drawing for band map
- `Views/Activation/RovePlannerView.swift` — Map-based rove stop planner
- `Views/Activation/ParkSearchField.swift` — Park search with typeahead
- `Views/Activation/OperatorChipsView.swift` — Operator chip list
- `Views/Settings/POTASettingsTab.swift` — POTA settings (license class, spotting)
- `Services/Spots/POTASpotService.swift` — Self-spot posting and re-spot timer

- [ ] **Step 2: Add CHANGELOG entry**

Under `[Unreleased]` → `Added`:
```markdown
- CW Sweep: POTA session setup wizard with inline band map, park search, rove planner
- CW Sweep: Regulated band map showing operator class privilege boundaries
- CW Sweep: Map-based rove stop planner with distance calculation
- CW Sweep: POTA spotting commands (SPOT, Edit Comment, Return to My Frequency ⌘⇧R)
- CW Sweep: P2P spot highlighting with double-click-to-tune
- CW Sweep: POTA settings tab (license class, auto-spot, re-spot timer)
- CarrierWaveCore: US operator class band privilege data (BandPlanPrivileges)
```

- [ ] **Step 3: Commit**

```bash
git add docs/FILE_INDEX.md CHANGELOG.md
git commit -m "docs: update FILE_INDEX and CHANGELOG for POTA session wizard"
```
