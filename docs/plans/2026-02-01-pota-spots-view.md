# POTA Spots View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a dedicated POTA spots view that shows active activations, filtered by band/mode, with "Calls of Note" section for highlighted callsigns.

**Architecture:** New `POTASpotsView` as a panel accessible via `POTA` command in logger. Uses existing `POTAClient.fetchActiveSpots()` API. Spots grouped by band with section headers. Filter chips for band/mode selection. Integrates with session's current band/mode as default filter.

**Tech Stack:** SwiftUI, existing POTAClient, POTAParksCache for park names

---

## Reference: PoLo Screenshot Analysis

From the screenshot, key UI elements:
- **Header**: "Spots" title with filter chip showing "All Bands • CW"
- **Subheader**: "Showing 23 out of 67 Spots" count
- **Section headers**: "Calls of Note" (highlighted), band groupings like "20m"
- **Spot rows**: Frequency (with sub-kHz), Callsign + icons, time ago, Park info on second line
- **Row format**: `14.031.900  KI5GTR ⚓  11m ago` / `20m  CW  🌲 US-7180: AR • Holland Bottoms St...`

---

## Task 1: Add POTA Command to LoggerCommand

**Files:**
- Modify: `CarrierWave/Models/LoggerCommand.swift`

### Step 1: Add pota case to enum

Add after the `rbn` case:

```swift
/// Show POTA spots panel
case pota
```

### Step 2: Add to helpText

Update the `helpText` static property, add after the RBN line:

```swift
POTA            - Show POTA activator spots
```

### Step 3: Add description

Add to the `description` computed property switch:

```swift
case .pota:
    "Show POTA spots"
```

### Step 4: Add icon

Add to the `icon` computed property switch:

```swift
case .pota:
    "tree.fill"
```

### Step 5: Add parser for POTA command

Add a new parser method:

```swift
private static func parsePOTA(upper: String) -> LoggerCommand? {
    if upper == "POTA" || upper == "SPOTS" {
        return .pota
    }
    return nil
}
```

### Step 6: Call parser in parse() method

In the `parse()` method, add after `parseRBN`:

```swift
if let cmd = parsePOTA(upper: upper) {
    return cmd
}
```

### Step 7: Add to suggestions

Add to `allSuggestions`:

```swift
// POTA
CommandSuggestion(
    command: "POTA", description: "Show POTA activator spots",
    icon: "tree.fill", prefixes: ["PO"], exact: ["P"]
),
```

### Step 8: Commit

```bash
git add CarrierWave/Models/LoggerCommand.swift
git commit -m "feat: add POTA command to logger"
```

---

## Task 2: Create POTASpotRow Component

**Files:**
- Create: `CarrierWave/Views/Logger/POTASpotsView.swift`

### Step 1: Create the file with POTASpotRow

```swift
import SwiftUI

// MARK: - POTASpotRow

/// A row displaying a single POTA spot
struct POTASpotRow: View {
    let spot: POTASpot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Frequency column
                VStack(alignment: .trailing, spacing: 2) {
                    frequencyDisplay
                    bandModeDisplay
                }
                .frame(width: 80, alignment: .trailing)

                // Callsign and park info
                VStack(alignment: .leading, spacing: 2) {
                    callsignRow
                    parkInfoRow
                }

                Spacer()

                // Time ago
                Text(spot.timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private var frequencyDisplay: some View {
        Group {
            if let freqKHz = spot.frequencyKHz {
                // Format as MHz with sub-kHz precision like "14.031.900"
                let mhz = freqKHz / 1000.0
                let formatted = formatFrequencyWithSubKHz(mhz)
                Text(formatted)
                    .font(.subheadline.monospaced())
            } else {
                Text(spot.frequency)
                    .font(.subheadline.monospaced())
            }
        }
    }

    private var bandModeDisplay: some View {
        HStack(spacing: 4) {
            if let band = deriveBand(from: spot.frequencyKHz) {
                Text(band)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(spot.mode)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var callsignRow: some View {
        HStack(spacing: 4) {
            Text(spot.activator)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(.primary)

            // Activity type icon based on reference prefix
            if spot.reference.hasPrefix("K-") || spot.reference.hasPrefix("US-") {
                Image(systemName: "tree.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if spot.reference.contains("FF-") {
                // Flora & Fauna
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "mappin.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    private var parkInfoRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "tree.fill")
                .font(.caption2)
                .foregroundStyle(.green)

            Text(parkDisplayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var parkDisplayText: String {
        var parts: [String] = [spot.reference]

        // Add location if available
        if let loc = spot.locationDesc, !loc.isEmpty {
            // Extract state from "US-CA" format
            let state = loc.components(separatedBy: "-").last ?? loc
            parts.append(state)
        }

        // Add park name if available
        if let name = spot.parkName, !name.isEmpty {
            parts.append(name)
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - Helpers

    private func formatFrequencyWithSubKHz(_ mhz: Double) -> String {
        // Format like "14.031.900" for 14031.9 kHz
        let wholeMHz = Int(mhz)
        let remainder = mhz - Double(wholeMHz)
        let kHz = Int(remainder * 1000)
        let subKHz = Int((remainder * 1000 - Double(kHz)) * 1000)

        if subKHz > 0 {
            return String(format: "%d.%03d.%03d", wholeMHz, kHz, subKHz)
        } else {
            return String(format: "%d.%03d", wholeMHz, kHz)
        }
    }

    private func deriveBand(from frequencyKHz: Double?) -> String? {
        guard let kHz = frequencyKHz else { return nil }
        let mhz = kHz / 1000.0

        switch mhz {
        case 1.8 ..< 2.0: return "160m"
        case 3.5 ..< 4.0: return "80m"
        case 5.3 ..< 5.4: return "60m"
        case 7.0 ..< 7.3: return "40m"
        case 10.1 ..< 10.15: return "30m"
        case 14.0 ..< 14.35: return "20m"
        case 18.068 ..< 18.168: return "17m"
        case 21.0 ..< 21.45: return "15m"
        case 24.89 ..< 24.99: return "12m"
        case 28.0 ..< 29.7: return "10m"
        case 50.0 ..< 54.0: return "6m"
        case 144.0 ..< 148.0: return "2m"
        case 420.0 ..< 450.0: return "70cm"
        default: return nil
        }
    }
}
```

### Step 2: Commit

```bash
git add CarrierWave/Views/Logger/POTASpotsView.swift
git commit -m "feat: add POTASpotRow component"
```

---

## Task 3: Create POTASpotsView Main View

**Files:**
- Modify: `CarrierWave/Views/Logger/POTASpotsView.swift`

### Step 1: Add filter state enum

Add at the top of the file after imports:

```swift
// MARK: - BandFilter

/// Band filter options for spots
enum BandFilter: String, CaseIterable, Identifiable {
    case all = "All Bands"
    case band160m = "160m"
    case band80m = "80m"
    case band60m = "60m"
    case band40m = "40m"
    case band30m = "30m"
    case band20m = "20m"
    case band17m = "17m"
    case band15m = "15m"
    case band12m = "12m"
    case band10m = "10m"
    case band6m = "6m"
    case band2m = "2m"

    var id: String { rawValue }

    var bandName: String? {
        if self == .all { return nil }
        return rawValue
    }

    static func from(bandName: String?) -> BandFilter {
        guard let name = bandName else { return .all }
        return allCases.first { $0.rawValue == name } ?? .all
    }
}

// MARK: - ModeFilter

/// Mode filter options for spots
enum ModeFilter: String, CaseIterable, Identifiable {
    case all = "All Modes"
    case cw = "CW"
    case ssb = "SSB"
    case ft8 = "FT8"
    case ft4 = "FT4"
    case digital = "Digital"

    var id: String { rawValue }

    var modeName: String? {
        if self == .all { return nil }
        return rawValue
    }

    func matches(_ mode: String) -> Bool {
        switch self {
        case .all: return true
        case .cw: return mode.uppercased() == "CW"
        case .ssb: return ["SSB", "USB", "LSB", "AM", "FM"].contains(mode.uppercased())
        case .ft8: return mode.uppercased() == "FT8"
        case .ft4: return mode.uppercased() == "FT4"
        case .digital: return ["FT8", "FT4", "RTTY", "PSK31", "PSK", "JT65", "JT9", "DATA", "DIGITAL"].contains(mode.uppercased())
        }
    }

    static func from(modeName: String?) -> ModeFilter {
        guard let name = modeName?.uppercased() else { return .all }
        switch name {
        case "CW": return .cw
        case "SSB", "USB", "LSB": return .ssb
        case "FT8": return .ft8
        case "FT4": return .ft4
        default: return .all
        }
    }
}
```

### Step 2: Add POTASpotsView struct

Add after the filter enums:

```swift
// MARK: - POTASpotsView

/// Panel showing active POTA spots with filtering
struct POTASpotsView: View {
    // MARK: Lifecycle

    init(
        initialBand: String? = nil,
        initialMode: String? = nil,
        onDismiss: @escaping () -> Void,
        onSelectSpot: ((POTASpot) -> Void)? = nil
    ) {
        self.onDismiss = onDismiss
        self.onSelectSpot = onSelectSpot
        // Set initial filters based on session band/mode
        _bandFilter = State(initialValue: BandFilter.from(bandName: initialBand))
        _modeFilter = State(initialValue: ModeFilter.from(modeName: initialMode))
    }

    // MARK: Internal

    let onDismiss: () -> Void
    let onSelectSpot: ((POTASpot) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if filteredSpots.isEmpty {
                emptyView
            } else {
                spotsList
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await loadSpots()
        }
    }

    // MARK: Private

    @State private var allSpots: [POTASpot] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var bandFilter: BandFilter
    @State private var modeFilter: ModeFilter
    @State private var showFilterSheet = false

    private var filteredSpots: [POTASpot] {
        allSpots.filter { spot in
            // Band filter
            if let targetBand = bandFilter.bandName {
                guard let spotBand = deriveBand(from: spot.frequencyKHz),
                      spotBand == targetBand else {
                    return false
                }
            }

            // Mode filter
            guard modeFilter.matches(spot.mode) else {
                return false
            }

            return true
        }
    }

    /// Spots grouped by band for section display
    private var spotsByBand: [(band: String, spots: [POTASpot])] {
        let grouped = Dictionary(grouping: filteredSpots) { spot -> String in
            deriveBand(from: spot.frequencyKHz) ?? "Other"
        }

        // Sort bands in frequency order
        let bandOrder = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm", "Other"]

        return grouped.sorted { lhs, rhs in
            let lhsIdx = bandOrder.firstIndex(of: lhs.key) ?? 999
            let rhsIdx = bandOrder.firstIndex(of: rhs.key) ?? 999
            return lhsIdx < rhsIdx
        }.map { (band: $0.key, spots: $0.value.sorted { ($0.frequencyKHz ?? 0) < ($1.frequencyKHz ?? 0) }) }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "tree.fill")
                .foregroundStyle(.green)

            Text("POTA Spots")
                .font(.headline)

            Spacer()

            Button {
                Task { await loadSpots() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Filter chip button
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                    Text(filterDisplayText)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFilterSheet) {
                filterSheet
            }

            // Count display
            Text("Showing \(filteredSpots.count) of \(allSpots.count) Spots")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var filterDisplayText: String {
        let bandText = bandFilter == .all ? "All Bands" : bandFilter.rawValue
        let modeText = modeFilter == .all ? "All Modes" : modeFilter.rawValue

        if bandFilter == .all && modeFilter == .all {
            return "All Spots"
        } else if modeFilter == .all {
            return bandText
        } else if bandFilter == .all {
            return modeText
        } else {
            return "\(bandText) • \(modeText)"
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Band") {
                    Picker("Band", selection: $bandFilter) {
                        ForEach(BandFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Mode") {
                    Picker("Mode", selection: $modeFilter) {
                        ForEach(ModeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Filter Spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showFilterSheet = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        bandFilter = .all
                        modeFilter = .all
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading POTA spots...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadSpots() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tree")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No spots match filters")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if bandFilter != .all || modeFilter != .all {
                Button("Clear Filters") {
                    bandFilter = .all
                    modeFilter = .all
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var spotsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(spotsByBand, id: \.band) { section in
                    Section {
                        ForEach(section.spots) { spot in
                            POTASpotRow(spot: spot) {
                                onSelectSpot?(spot)
                            }
                            Divider()
                                .padding(.leading, 92)
                        }
                    } header: {
                        sectionHeader(section.band)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private func sectionHeader(_ band: String) -> some View {
        HStack {
            Text(band)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Data Loading

    private func loadSpots() async {
        isLoading = true
        errorMessage = nil

        do {
            let client = POTAClient(authService: POTAAuthService())
            allSpots = try await client.fetchActiveSpots()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Helpers

    private func deriveBand(from frequencyKHz: Double?) -> String? {
        guard let kHz = frequencyKHz else { return nil }
        let mhz = kHz / 1000.0

        switch mhz {
        case 1.8 ..< 2.0: return "160m"
        case 3.5 ..< 4.0: return "80m"
        case 5.3 ..< 5.4: return "60m"
        case 7.0 ..< 7.3: return "40m"
        case 10.1 ..< 10.15: return "30m"
        case 14.0 ..< 14.35: return "20m"
        case 18.068 ..< 18.168: return "17m"
        case 21.0 ..< 21.45: return "15m"
        case 24.89 ..< 24.99: return "12m"
        case 28.0 ..< 29.7: return "10m"
        case 50.0 ..< 54.0: return "6m"
        case 144.0 ..< 148.0: return "2m"
        case 420.0 ..< 450.0: return "70cm"
        default: return nil
        }
    }
}

// MARK: - Preview

#Preview {
    POTASpotsView(
        initialBand: "20m",
        initialMode: "CW",
        onDismiss: {}
    )
    .frame(height: 500)
    .padding()
}
```

### Step 3: Commit

```bash
git add CarrierWave/Views/Logger/POTASpotsView.swift
git commit -m "feat: add POTASpotsView with filtering"
```

---

## Task 4: Integrate POTASpotsView into LoggerView

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

### Step 1: Add state for POTA panel

Find the command panel state variables (around line 275) and add:

```swift
@State private var showPOTAPanel = false
```

### Step 2: Add panel overlay

Find the `panelOverlays` computed property and add a new panel for POTA:

```swift
if showPOTAPanel {
    SwipeToDismissPanel(isPresented: $showPOTAPanel) {
        POTASpotsView(
            initialBand: sessionManager?.activeSession?.band,
            initialMode: sessionManager?.activeSession?.mode,
            onDismiss: { showPOTAPanel = false },
            onSelectSpot: { spot in
                // Could auto-fill frequency from spot
                if let freqKHz = spot.frequencyKHz {
                    let freqMHz = freqKHz / 1000.0
                    _ = sessionManager?.updateFrequency(freqMHz)
                    ToastManager.shared.info("Tuned to \(FrequencyFormatter.formatWithUnit(freqMHz))")
                }
            }
        )
    }
    .padding()
    .transition(.move(edge: .bottom).combined(with: .opacity))
}
```

Also add animation for the new panel in the same view:

```swift
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: showPOTAPanel)
```

### Step 3: Handle POTA command in executeCommand

Find the `executeCommand(_ command:)` method and add a case for POTA:

```swift
case .pota:
    showPOTAPanel = true
```

### Step 4: Commit

```bash
git add CarrierWave/Views/Logger/LoggerView.swift
git commit -m "feat: integrate POTASpotsView into logger"
```

---

## Task 5: Update File Index and Changelog

**Files:**
- Modify: `docs/FILE_INDEX.md`
- Modify: `CHANGELOG.md`

### Step 1: Update FILE_INDEX.md

Add to the Logger section:

```markdown
| `POTASpotsView.swift` | POTA activator spots panel with band/mode filtering |
```

### Step 2: Update CHANGELOG.md

Add to Unreleased/Added:

```markdown
- **POTA Spots Panel** - Dedicated view for active POTA activator spots
  - Filter by band and mode (defaults to session's current band/mode)
  - Grouped by band with section headers
  - Tap spot to tune to frequency
  - Access via `POTA` command in logger
```

### Step 3: Commit

```bash
git add docs/FILE_INDEX.md CHANGELOG.md
git commit -m "docs: add POTA spots view to file index and changelog"
```

---

## Summary

This plan implements a dedicated POTA spots view with:

1. **New `POTA` command** - Type "POTA" or "SPOTS" in logger to open the panel
2. **Filter system** - Band and mode filters, defaulting to session's current settings
3. **Grouped display** - Spots grouped by band with sticky section headers
4. **Spot rows** - Frequency with sub-kHz precision, callsign, park info, time ago
5. **Tune on tap** - Tapping a spot tunes your radio to that frequency

Total new files: 1 (`POTASpotsView.swift`)
Modified files: 3 (`LoggerCommand.swift`, `LoggerView.swift`, docs)
