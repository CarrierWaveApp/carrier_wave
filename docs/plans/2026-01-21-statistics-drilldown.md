# Statistics Drilldown Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make dashboard stat boxes tappable to show detailed breakdowns with expandable QSO lists.

**Architecture:** Add `StatCategoryType` enum for routing, `StatDetailView` for drilldown screens, `StatItemRow` for expandable list items. Lift tab selection to `ContentView` for "Total QSOs" to switch tabs.

**Tech Stack:** SwiftUI, SwiftData

---

## Task 1: Create StatCategoryType Enum

**Files:**
- Create: `FullDuplex/Models/StatCategoryType.swift`

**Step 1: Create the enum file**

```swift
import Foundation

enum StatCategoryType: String, CaseIterable, Identifiable {
    case entities
    case grids
    case bands
    case modes
    case parks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .entities: return "Entities"
        case .grids: return "Grids"
        case .bands: return "Bands"
        case .modes: return "Modes"
        case .parks: return "Parks"
        }
    }

    var icon: String {
        switch self {
        case .entities: return "globe"
        case .grids: return "square.grid.3x3"
        case .bands: return "waveform"
        case .modes: return "dot.radiowaves.right"
        case .parks: return "leaf"
        }
    }
}
```

**Step 2: Build to verify no errors**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add FullDuplex/Models/StatCategoryType.swift
git commit -m "feat: add StatCategoryType enum for stat drilldown routing"
```

---

## Task 2: Create StatCategoryItem Model

**Files:**
- Create: `FullDuplex/Models/StatCategoryItem.swift`

**Step 1: Create the model file**

```swift
import Foundation

struct StatCategoryItem: Identifiable {
    let id: String
    let identifier: String
    let description: String
    let count: Int
    let qsos: [QSO]

    init(identifier: String, description: String, qsos: [QSO]) {
        self.id = identifier
        self.identifier = identifier
        self.description = description
        self.count = qsos.count
        self.qsos = qsos.sorted { $0.timestamp > $1.timestamp }
    }
}
```

**Step 2: Build to verify no errors**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add FullDuplex/Models/StatCategoryItem.swift
git commit -m "feat: add StatCategoryItem model for grouped QSO data"
```

---

## Task 3: Create Description Lookup Services

**Files:**
- Create: `FullDuplex/Services/DescriptionLookup.swift`

**Step 1: Create the lookup service**

```swift
import Foundation

struct DescriptionLookup {

    // MARK: - Entity Descriptions (Callsign Prefix -> Country)

    static func entityDescription(for prefix: String) -> String {
        let upper = prefix.uppercased()

        // Common prefixes - expand as needed
        let entities: [String: String] = [
            // USA
            "K": "United States", "W": "United States", "N": "United States", "A": "United States",
            // Europe
            "G": "England", "M": "England",
            "F": "France",
            "DL": "Germany", "DA": "Germany", "DB": "Germany", "DC": "Germany", "DD": "Germany", "DF": "Germany", "DG": "Germany", "DH": "Germany", "DI": "Germany", "DJ": "Germany", "DK": "Germany", "DM": "Germany", "DO": "Germany", "DP": "Germany", "DQ": "Germany", "DR": "Germany",
            "I": "Italy",
            "EA": "Spain", "EB": "Spain", "EC": "Spain", "ED": "Spain", "EE": "Spain", "EF": "Spain", "EG": "Spain", "EH": "Spain",
            "PA": "Netherlands", "PB": "Netherlands", "PC": "Netherlands", "PD": "Netherlands", "PE": "Netherlands", "PF": "Netherlands", "PG": "Netherlands", "PH": "Netherlands", "PI": "Netherlands",
            "ON": "Belgium",
            "OE": "Austria",
            "HB": "Switzerland", "HB9": "Switzerland",
            "SM": "Sweden",
            "LA": "Norway",
            "OZ": "Denmark",
            "OH": "Finland",
            "SP": "Poland",
            "OK": "Czech Republic",
            "OM": "Slovakia",
            "HA": "Hungary",
            "YO": "Romania",
            "LZ": "Bulgaria",
            "SV": "Greece",
            "YU": "Serbia",
            "9A": "Croatia",
            "S5": "Slovenia",
            // UK
            "GW": "Wales", "GM": "Scotland", "GI": "Northern Ireland", "GD": "Isle of Man", "GJ": "Jersey", "GU": "Guernsey",
            // Americas
            "VE": "Canada", "VA": "Canada", "VY": "Canada", "VO": "Canada",
            "XE": "Mexico", "XA": "Mexico", "XB": "Mexico", "XC": "Mexico", "XD": "Mexico", "XF": "Mexico",
            "LU": "Argentina",
            "PY": "Brazil", "PP": "Brazil", "PQ": "Brazil", "PR": "Brazil", "PS": "Brazil", "PT": "Brazil", "PU": "Brazil", "PV": "Brazil", "PW": "Brazil", "PX": "Brazil",
            "CE": "Chile",
            "HK": "Colombia",
            "HC": "Ecuador",
            "OA": "Peru",
            "YV": "Venezuela",
            // Asia/Pacific
            "JA": "Japan", "JD": "Japan", "JE": "Japan", "JF": "Japan", "JG": "Japan", "JH": "Japan", "JI": "Japan", "JJ": "Japan", "JK": "Japan", "JL": "Japan", "JM": "Japan", "JN": "Japan", "JO": "Japan", "JP": "Japan", "JQ": "Japan", "JR": "Japan", "JS": "Japan",
            "HL": "South Korea",
            "BV": "Taiwan",
            "VK": "Australia",
            "ZL": "New Zealand",
            "DU": "Philippines",
            "HS": "Thailand",
            "9M": "Malaysia",
            "9V": "Singapore",
            "YB": "Indonesia",
            "VU": "India",
            // Russia
            "UA": "Russia", "R": "Russia",
            // Africa
            "ZS": "South Africa",
            "SU": "Egypt",
            "CN": "Morocco",
            "EA8": "Canary Islands", "EA9": "Ceuta & Melilla",
            // Caribbean
            "KP4": "Puerto Rico", "KP3": "Puerto Rico", "NP4": "Puerto Rico", "WP4": "Puerto Rico",
            "KP2": "US Virgin Islands",
            "KH6": "Hawaii",
            "KL7": "Alaska",
        ]

        // Try exact match first
        if let desc = entities[upper] {
            return desc
        }

        // Try progressively shorter prefixes
        for length in stride(from: min(upper.count, 3), through: 1, by: -1) {
            let shortPrefix = String(upper.prefix(length))
            if let desc = entities[shortPrefix] {
                return desc
            }
        }

        return "Unknown"
    }

    // MARK: - Band Descriptions

    static func bandDescription(for band: String) -> String {
        let descriptions: [String: String] = [
            "160m": "1.8 MHz",
            "80m": "3.5 MHz",
            "60m": "5 MHz",
            "40m": "7 MHz",
            "30m": "10 MHz",
            "20m": "14 MHz",
            "17m": "18 MHz",
            "15m": "21 MHz",
            "12m": "24 MHz",
            "10m": "28 MHz",
            "6m": "50 MHz",
            "2m": "144 MHz",
            "70cm": "430 MHz",
            "23cm": "1.2 GHz",
        ]
        return descriptions[band.lowercased()] ?? ""
    }

    // MARK: - Mode Descriptions

    static func modeDescription(for mode: String) -> String {
        let descriptions: [String: String] = [
            "SSB": "Single Sideband Voice",
            "LSB": "Lower Sideband Voice",
            "USB": "Upper Sideband Voice",
            "CW": "Continuous Wave (Morse)",
            "FM": "Frequency Modulation Voice",
            "AM": "Amplitude Modulation Voice",
            "FT8": "Digital - FT8",
            "FT4": "Digital - FT4",
            "JS8": "Digital - JS8Call",
            "RTTY": "Radio Teletype",
            "PSK31": "Digital - PSK31",
            "SSTV": "Slow-Scan Television",
            "MFSK": "Multi-Frequency Shift Keying",
            "OLIVIA": "Digital - Olivia",
            "JT65": "Digital - JT65",
            "JT9": "Digital - JT9",
            "WSPR": "Weak Signal Propagation Reporter",
        ]
        return descriptions[mode.uppercased()] ?? ""
    }

    // MARK: - Grid Descriptions

    static func gridDescription(for grid: String) -> String {
        // Grid squares are geographic - could expand to show region names
        // For now, return empty (grid itself is descriptive)
        return ""
    }

    // MARK: - Park Descriptions

    static func parkDescription(for parkReference: String) -> String {
        // Park names would come from QSO data or POTA API
        // For now, return empty
        return ""
    }
}
```

**Step 2: Build to verify no errors**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add FullDuplex/Services/DescriptionLookup.swift
git commit -m "feat: add DescriptionLookup service for entity/band/mode descriptions"
```

---

## Task 4: Add QSO Grouping to QSOStatistics

**Files:**
- Modify: `FullDuplex/Views/Dashboard/DashboardView.swift` (lines 352-385)

**Step 1: Add grouping methods to QSOStatistics**

Add these methods to the `QSOStatistics` struct after the `activityByDate` property (after line 384):

```swift
    func items(for category: StatCategoryType) -> [StatCategoryItem] {
        switch category {
        case .entities:
            return groupedByEntity()
        case .grids:
            return groupedByGrid()
        case .bands:
            return groupedByBand()
        case .modes:
            return groupedByMode()
        case .parks:
            return groupedByPark()
        }
    }

    private func groupedByEntity() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: qsos) { $0.callsignPrefix }
        return grouped.map { prefix, qsos in
            StatCategoryItem(
                identifier: prefix,
                description: DescriptionLookup.entityDescription(for: prefix),
                qsos: qsos
            )
        }
    }

    private func groupedByGrid() -> [StatCategoryItem] {
        let gridsOnly = qsos.filter { $0.theirGrid != nil && !$0.theirGrid!.isEmpty }
        let grouped = Dictionary(grouping: gridsOnly) { $0.theirGrid! }
        return grouped.map { grid, qsos in
            StatCategoryItem(
                identifier: grid,
                description: DescriptionLookup.gridDescription(for: grid),
                qsos: qsos
            )
        }
    }

    private func groupedByBand() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: qsos) { $0.band }
        return grouped.map { band, qsos in
            StatCategoryItem(
                identifier: band,
                description: DescriptionLookup.bandDescription(for: band),
                qsos: qsos
            )
        }
    }

    private func groupedByMode() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: qsos) { $0.mode }
        return grouped.map { mode, qsos in
            StatCategoryItem(
                identifier: mode,
                description: DescriptionLookup.modeDescription(for: mode),
                qsos: qsos
            )
        }
    }

    private func groupedByPark() -> [StatCategoryItem] {
        let parksOnly = qsos.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let grouped = Dictionary(grouping: parksOnly) { $0.parkReference! }
        return grouped.map { park, qsos in
            StatCategoryItem(
                identifier: park,
                description: DescriptionLookup.parkDescription(for: park),
                qsos: qsos
            )
        }
    }
```

**Step 2: Build to verify no errors**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add FullDuplex/Views/Dashboard/DashboardView.swift
git commit -m "feat: add QSO grouping methods to QSOStatistics"
```

---

## Task 5: Create StatItemRow Component

**Files:**
- Create: `FullDuplex/Views/Dashboard/StatItemRow.swift`

**Step 1: Create the expandable row component**

```swift
import SwiftUI

struct StatItemRow: View {
    let item: StatCategoryItem

    @State private var isExpanded = false
    @State private var visibleQSOCount = 5

    private let batchSize = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - tappable
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        visibleQSOCount = batchSize
                    }
                }
            } label: {
                headerRow
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.identifier)
                    .font(.headline)
                Spacer()
                Text("\(item.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !item.description.isEmpty {
                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.top, 8)

            ForEach(item.qsos.prefix(visibleQSOCount)) { qso in
                qsoRow(qso)
            }

            if visibleQSOCount < item.qsos.count {
                Button {
                    withAnimation {
                        visibleQSOCount += batchSize
                    }
                } label: {
                    HStack {
                        Image(systemName: "ellipsis")
                        Text("Show more (\(item.qsos.count - visibleQSOCount) remaining)")
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
                .padding(.top, 4)
            }
        }
        .padding(.leading, 16)
    }

    private func qsoRow(_ qso: QSO) -> some View {
        HStack {
            Text(qso.callsign)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Text(qso.band)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .clipShape(Capsule())

            Text(qso.mode)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(qso.timestamp, style: .date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
```

**Step 2: Build to verify no errors**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add FullDuplex/Views/Dashboard/StatItemRow.swift
git commit -m "feat: add StatItemRow expandable component"
```

---

## Task 6: Create StatDetailView

**Files:**
- Create: `FullDuplex/Views/Dashboard/StatDetailView.swift`

**Step 1: Create the detail view**

```swift
import SwiftUI

struct StatDetailView: View {
    let category: StatCategoryType
    let items: [StatCategoryItem]

    @State private var sortByCount = true

    private var sortedItems: [StatCategoryItem] {
        if sortByCount {
            return items.sorted { $0.count > $1.count }
        } else {
            return items.sorted { $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            ForEach(sortedItems) { item in
                StatItemRow(item: item)
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sortByCount = true
                    } label: {
                        Label("By Count", systemImage: sortByCount ? "checkmark" : "")
                    }

                    Button {
                        sortByCount = false
                    } label: {
                        Label("A-Z", systemImage: sortByCount ? "" : "checkmark")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }
}
```

**Step 2: Build to verify no errors**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add FullDuplex/Views/Dashboard/StatDetailView.swift
git commit -m "feat: add StatDetailView for category drilldown"
```

---

## Task 7: Lift Tab Selection State to ContentView

**Files:**
- Modify: `FullDuplex/ContentView.swift`

**Step 1: Add tab selection state and binding**

Replace the entire `ContentView.swift` with:

```swift
import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case dashboard
    case logs
    case settings
}

struct ContentView: View {
    @StateObject private var iCloudMonitor = ICloudMonitor()
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(iCloudMonitor: iCloudMonitor, selectedTab: $selectedTab)
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
                .tag(AppTab.dashboard)

            LogsListView()
                .tabItem {
                    Label("Logs", systemImage: "list.bullet")
                }
                .tag(AppTab.logs)

            SettingsMainView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .onAppear {
            iCloudMonitor.startMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveADIFFile)) { notification in
            if let url = notification.object as? URL {
                // Handle import - for now just print
                print("Received ADIF file: \(url.lastPathComponent)")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [QSO.self, SyncRecord.self, UploadDestination.self], inMemory: true)
}
```

**Step 2: Build - expect error (DashboardView signature changed)**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10`

Expected: Build error about DashboardView missing `selectedTab` parameter (will fix in next task)

**Step 3: Commit (partial - will complete in Task 8)**

```bash
git add FullDuplex/ContentView.swift
git commit -m "feat: add AppTab enum and lift tab selection to ContentView"
```

---

## Task 8: Update DashboardView with Tab Binding and Tappable Stats

**Files:**
- Modify: `FullDuplex/Views/Dashboard/DashboardView.swift`

**Step 1: Add selectedTab binding to DashboardView**

At line 4 (after the struct declaration), add:

```swift
    @Binding var selectedTab: AppTab
```

**Step 2: Update the summaryCard to use NavigationLinks**

Replace the `summaryCard` computed property (lines 105-134) with:

```swift
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Statistics")
                    .font(.headline)
                Spacer()
                if let lastSync = lastSyncDate {
                    Text("Synced \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                // Total QSOs - switches to Logs tab
                Button {
                    selectedTab = .logs
                } label: {
                    StatBox(title: "QSOs", value: "\(stats.totalQSOs)", icon: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.plain)

                // Category stats - navigate to detail views
                NavigationLink {
                    StatDetailView(category: .entities, items: stats.items(for: .entities))
                } label: {
                    StatBox(title: "Entities", value: "\(stats.uniqueEntities)", icon: "globe")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .grids, items: stats.items(for: .grids))
                } label: {
                    StatBox(title: "Grids", value: "\(stats.uniqueGrids)", icon: "square.grid.3x3")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .bands, items: stats.items(for: .bands))
                } label: {
                    StatBox(title: "Bands", value: "\(stats.uniqueBands)", icon: "waveform")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .modes, items: stats.items(for: .modes))
                } label: {
                    StatBox(title: "Modes", value: "\(stats.uniqueModes)", icon: "dot.radiowaves.right")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .parks, items: stats.items(for: .parks))
                } label: {
                    StatBox(title: "Parks", value: "\(stats.uniqueParks)", icon: "leaf")
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
```

**Step 3: Build to verify no errors**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add FullDuplex/Views/Dashboard/DashboardView.swift
git commit -m "feat: make stat boxes tappable with navigation to detail views"
```

---

## Task 9: Run Tests and Verify

**Files:**
- No changes

**Step 1: Run full test suite**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "(Test case|passed|failed|BUILD)"`

Expected: All tests pass

**Step 2: If tests fail, fix and re-run**

Address any failures before proceeding.

---

## Task 10: Final Commit and Summary

**Step 1: Verify git log**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && git log --oneline -10`

Expected: 7-8 commits for this feature

**Step 2: Review changes**

Run: `cd /Users/jsvana/projects/FullDuplex/.worktrees/statistics-drilldown && git diff main --stat`

Review the summary of changes.

---

## Summary of Files Created/Modified

**New files:**
- `FullDuplex/Models/StatCategoryType.swift` - Enum for stat category routing
- `FullDuplex/Models/StatCategoryItem.swift` - Model for grouped QSO data
- `FullDuplex/Services/DescriptionLookup.swift` - Lookup service for entity/band/mode descriptions
- `FullDuplex/Views/Dashboard/StatItemRow.swift` - Expandable row component
- `FullDuplex/Views/Dashboard/StatDetailView.swift` - Detail view for category drilldown

**Modified files:**
- `FullDuplex/ContentView.swift` - Added AppTab enum, lifted tab selection state
- `FullDuplex/Views/Dashboard/DashboardView.swift` - Added tab binding, made stat boxes tappable, added grouping methods
