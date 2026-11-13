# Logger Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enhance the QSO logger with improved park entry (search by name, nearby parks, number shorthand), add State field, and reorganize Notes/RST layout.

**Architecture:** Extend POTAParksCache to support full-text search and geospatial queries. Add new UI components for park picker with search/nearby tabs. Reorganize LoggerView field layout with State field and repositioned Notes/RST.

**Tech Stack:** SwiftUI, SwiftData, CoreLocation, existing POTAParksCache

---

## Summary of Changes

1. **Park lookup by name** - Search parks by name in the park entry field
2. **Nearby parks** - Show parks near user's grid square location
3. **Park number shorthand** - Type "1234" → infer "US-1234" based on user's QTH/grid
4. **State field** - Add State entry next to Callsign
5. **Notes field** - Move below Callsign row
6. **RST fields** - Make smaller, position next to Notes

---

## Task 1: Extend POTAParksCache with Search Capabilities

**Files:**
- Modify: `CarrierWave/Services/POTAParksCache.swift`

**Goal:** Add ability to search parks by name and find nearby parks by coordinates.

### Step 1: Add park data structure with full metadata

Add a struct to hold complete park data (not just name):

```swift
// Add after POTAParksCacheStatus enum

/// Complete park data from POTA CSV
struct POTAPark: Sendable {
    let reference: String      // "US-1234"
    let name: String           // "Yellowstone National Park"
    let locationDesc: String   // "US-WY" (state/region)
    let latitude: Double?
    let longitude: Double?
    let grid: String?
    let entityId: Int          // DXCC entity (291 = USA)
    let isActive: Bool
    
    /// Extract country prefix from reference (e.g., "US" from "US-1234")
    var countryPrefix: String {
        reference.components(separatedBy: "-").first ?? ""
    }
    
    /// Extract numeric part from reference (e.g., "1234" from "US-1234")
    var numericPart: String {
        let parts = reference.components(separatedBy: "-")
        return parts.count > 1 ? parts[1] : ""
    }
    
    /// Extract state from locationDesc (e.g., "WY" from "US-WY")
    var state: String? {
        let parts = locationDesc.components(separatedBy: "-")
        return parts.count > 1 ? parts[1] : nil
    }
}
```

### Step 2: Update storage to use full park data

Replace the simple `[String: String]` dictionary with full park storage:

```swift
// Replace existing parks property
nonisolated(unsafe) private var parks: [String: POTAPark] = [:] // reference -> full park data

// Add search index for name lookups (lowercase name -> references)
nonisolated(unsafe) private var nameIndex: [String: [String]] = [:]
```

### Step 3: Update parseCSV to populate full park data

Replace the existing `parseCSV` method:

```swift
private func parseCSV(_ csv: String) -> [String: POTAPark] {
    var result: [String: POTAPark] = [:]
    let lines = csv.components(separatedBy: .newlines)

    // Skip header row
    for line in lines.dropFirst() {
        guard !line.isEmpty else { continue }

        let fields = parseCSVLine(line)
        // Expected: reference, name, active, entityId, locationDesc, latitude, longitude, grid
        guard fields.count >= 8 else { continue }

        let reference = fields[0].uppercased()
        let name = fields[1]
        let isActive = fields[2] == "1"
        let entityId = Int(fields[3]) ?? 0
        let locationDesc = fields[4]
        let latitude = Double(fields[5])
        let longitude = Double(fields[6])
        let grid = fields[7].isEmpty ? nil : fields[7]

        guard !reference.isEmpty, !name.isEmpty else { continue }
        
        result[reference] = POTAPark(
            reference: reference,
            name: name,
            locationDesc: locationDesc,
            latitude: latitude,
            longitude: longitude,
            grid: grid,
            entityId: entityId,
            isActive: isActive
        )
    }

    return result
}
```

### Step 4: Build name search index after loading

Add method to build the search index:

```swift
/// Build search index for park names (called after loading parks)
private func buildNameIndex() {
    var index: [String: [String]] = [:]
    
    for (reference, park) in parks {
        // Index by each word in the name (lowercase)
        let words = park.name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        
        for word in words {
            index[word, default: []].append(reference)
        }
    }
    
    nameIndex = index
}
```

Call this in `loadFromDisk()` and `downloadAndCache()` after setting `parks`:

```swift
// After: parks = parseCSV(csvData)
buildNameIndex()
```

### Step 5: Add search methods

```swift
/// Search parks by name (returns up to 20 results)
nonisolated func searchByName(_ query: String, limit: Int = 20) -> [POTAPark] {
    let queryWords = query.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 2 }
    
    guard !queryWords.isEmpty else { return [] }
    
    // Find parks matching all query words
    var matchingRefs: Set<String>?
    
    for word in queryWords {
        // Find all refs that contain this word prefix
        let matching = nameIndex.filter { $0.key.hasPrefix(word) }
            .flatMap { $0.value }
        
        if matchingRefs == nil {
            matchingRefs = Set(matching)
        } else {
            matchingRefs = matchingRefs!.intersection(matching)
        }
    }
    
    guard let refs = matchingRefs else { return [] }
    
    // Convert to parks and sort by relevance (exact match first, then alphabetical)
    let results = refs.compactMap { parks[$0] }
        .filter { $0.isActive }
        .sorted { p1, p2 in
            let name1 = p1.name.lowercased()
            let name2 = p2.name.lowercased()
            let q = query.lowercased()
            
            // Exact prefix match wins
            let p1Prefix = name1.hasPrefix(q)
            let p2Prefix = name2.hasPrefix(q)
            if p1Prefix != p2Prefix { return p1Prefix }
            
            // Then alphabetical
            return name1 < name2
        }
    
    return Array(results.prefix(limit))
}

/// Find parks near a coordinate (returns up to 10 nearest)
nonisolated func nearbyParks(
    latitude: Double,
    longitude: Double,
    limit: Int = 10,
    maxDistanceKm: Double = 100
) -> [(park: POTAPark, distanceKm: Double)] {
    let results = parks.values
        .filter { $0.isActive && $0.latitude != nil && $0.longitude != nil }
        .map { park -> (park: POTAPark, distanceKm: Double) in
            let dist = haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: park.latitude!, lon2: park.longitude!
            )
            return (park, dist)
        }
        .filter { $0.distanceKm <= maxDistanceKm }
        .sorted { $0.distanceKm < $1.distanceKm }
    
    return Array(results.prefix(limit))
}

/// Haversine formula for distance between two coordinates (in km)
private nonisolated func haversineDistance(
    lat1: Double, lon1: Double,
    lat2: Double, lon2: Double
) -> Double {
    let R = 6371.0 // Earth's radius in km
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat/2) * sin(dLat/2) +
            cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
            sin(dLon/2) * sin(dLon/2)
    let c = 2 * atan2(sqrt(a), sqrt(1-a))
    return R * c
}

/// Lookup park by reference, with number-only shorthand support
/// If query is just numbers (e.g., "1234"), infer prefix from defaultCountry
nonisolated func lookupPark(_ query: String, defaultCountry: String = "US") -> POTAPark? {
    let normalized = query.uppercased().trimmingCharacters(in: .whitespaces)
    
    // If it already has a dash, it's a full reference
    if normalized.contains("-") {
        return parks[normalized]
    }
    
    // If it's all digits, add the default country prefix
    if normalized.allSatisfy({ $0.isNumber }) {
        let fullRef = "\(defaultCountry)-\(normalized)"
        return parks[fullRef]
    }
    
    // Try as-is (maybe they typed "US1234" without dash)
    // Extract letters and numbers
    let letters = normalized.filter { $0.isLetter }
    let numbers = normalized.filter { $0.isNumber }
    if !letters.isEmpty, !numbers.isEmpty {
        let fullRef = "\(letters)-\(numbers)"
        return parks[fullRef]
    }
    
    return nil
}

/// Get full park data by reference
nonisolated func park(for reference: String) -> POTAPark? {
    parks[reference.uppercased()]
}
```

### Step 6: Update existing name() method for backwards compatibility

```swift
/// Get park name for a reference (backwards compatible)
func name(for reference: String) -> String? {
    parks[reference.uppercased()]?.name
}

/// Synchronous park name lookup (backwards compatible)
nonisolated func nameSync(for reference: String) -> String? {
    parks[reference.uppercased()]?.name
}
```

### Step 7: Commit

```bash
git add CarrierWave/Services/POTAParksCache.swift
git commit -m "feat: extend POTAParksCache with search and nearby parks"
```

---

## Task 2: Create Park Picker Sheet Component

**Files:**
- Create: `CarrierWave/Views/Logger/ParkPickerSheet.swift`

**Goal:** Create a sheet with tabs for searching parks by name and showing nearby parks.

### Step 1: Create the ParkPickerSheet view

```swift
import CoreLocation
import SwiftUI

// MARK: - ParkPickerSheet

/// Sheet for selecting a park by search or nearby location
struct ParkPickerSheet: View {
    // MARK: Lifecycle

    init(
        selectedPark: Binding<String>,
        userGrid: String?,
        defaultCountry: String = "US",
        onDismiss: @escaping () -> Void
    ) {
        self._selectedPark = selectedPark
        self.userGrid = userGrid
        self.defaultCountry = defaultCountry
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    enum Tab: String, CaseIterable {
        case search = "Search"
        case nearby = "Nearby"
    }

    @Binding var selectedPark: String

    let userGrid: String?
    let defaultCountry: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab content
                switch selectedTab {
                case .search:
                    searchTab
                case .nearby:
                    nearbyTab
                }
            }
            .navigationTitle("Select Park")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var selectedTab: Tab = .search
    @State private var searchText = ""
    @State private var searchResults: [POTAPark] = []
    @State private var nearbyParks: [(park: POTAPark, distanceKm: Double)] = []
    @State private var isLoadingNearby = false

    private var searchTab: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by park name...", text: $searchText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, newValue in
                        performSearch(newValue)
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))

            // Results list
            if searchResults.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "Search Parks",
                        systemImage: "magnifyingglass",
                        description: Text("Type a park name to search")
                    )
                } else {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "questionmark.circle",
                        description: Text("No parks match \"\(searchText)\"")
                    )
                }
            } else {
                List(searchResults, id: \.reference) { park in
                    ParkRow(park: park) {
                        selectPark(park)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var nearbyTab: some View {
        Group {
            if userGrid == nil {
                ContentUnavailableView(
                    "Grid Not Set",
                    systemImage: "location.slash",
                    description: Text("Set your grid square in Settings → About Me to see nearby parks")
                )
            } else if isLoadingNearby {
                ProgressView("Finding nearby parks...")
            } else if nearbyParks.isEmpty {
                ContentUnavailableView(
                    "No Nearby Parks",
                    systemImage: "map",
                    description: Text("No parks found within 100 km")
                )
            } else {
                List(nearbyParks, id: \.park.reference) { item in
                    ParkRow(park: item.park, distance: item.distanceKm) {
                        selectPark(item.park)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            loadNearbyParks()
        }
    }

    private func performSearch(_ query: String) {
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        searchResults = POTAParksCache.shared.searchByName(query)
    }

    private func loadNearbyParks() {
        guard let grid = userGrid,
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return
        }

        isLoadingNearby = true
        nearbyParks = POTAParksCache.shared.nearbyParks(
            latitude: coord.latitude,
            longitude: coord.longitude
        )
        isLoadingNearby = false
    }

    private func selectPark(_ park: POTAPark) {
        selectedPark = park.reference
        onDismiss()
    }
}

// MARK: - ParkRow

/// Row displaying a park with optional distance
struct ParkRow: View {
    let park: POTAPark
    var distance: Double?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(park.reference)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.green)
                    Text(park.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let state = park.state {
                        Text(state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let dist = distance {
                    Text(formatDistance(dist))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatDistance(_ km: Double) -> String {
        if km < 1 {
            return String(format: "%.0f m", km * 1000)
        } else if km < 10 {
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.0f km", km)
        }
    }
}

// MARK: - Preview

#Preview {
    ParkPickerSheet(
        selectedPark: .constant(""),
        userGrid: "FN31pr",
        onDismiss: {}
    )
}
```

### Step 2: Commit

```bash
git add CarrierWave/Views/Logger/ParkPickerSheet.swift
git commit -m "feat: add ParkPickerSheet with search and nearby tabs"
```

---

## Task 3: Create Enhanced Park Entry Field Component

**Files:**
- Create: `CarrierWave/Views/Logger/ParkEntryField.swift`

**Goal:** Create a text field that supports typing park references (with shorthand) and has a picker button.

### Step 1: Create ParkEntryField

```swift
import SwiftUI

// MARK: - ParkEntryField

/// Enhanced park entry field with search picker and number shorthand
struct ParkEntryField: View {
    // MARK: Lifecycle

    init(
        parkReference: Binding<String>,
        label: String = "Park",
        placeholder: String = "K-1234",
        userGrid: String?,
        defaultCountry: String = "US"
    ) {
        self._parkReference = parkReference
        self.label = label
        self.placeholder = placeholder
        self.userGrid = userGrid
        self.defaultCountry = defaultCountry
    }

    // MARK: Internal

    @Binding var parkReference: String

    let label: String
    let placeholder: String
    let userGrid: String?
    let defaultCountry: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(placeholder, text: $parkReference)
                    .font(.subheadline.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: parkReference) { _, newValue in
                        handleParkInput(newValue)
                    }

                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Show park name if valid reference entered
            if let parkName = resolvedParkName {
                Text(parkName)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showPicker) {
            ParkPickerSheet(
                selectedPark: $parkReference,
                userGrid: userGrid,
                defaultCountry: defaultCountry,
                onDismiss: { showPicker = false }
            )
        }
    }

    // MARK: Private

    @State private var showPicker = false
    @State private var resolvedParkName: String?

    /// Handle park input with number shorthand expansion
    private func handleParkInput(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).uppercased()
        
        // Look up the park (handles shorthand automatically)
        if let park = POTAParksCache.shared.lookupPark(trimmed, defaultCountry: defaultCountry) {
            resolvedParkName = park.name
            
            // If user typed shorthand, expand to full reference
            if !trimmed.contains("-"), trimmed.allSatisfy({ $0.isNumber }) {
                // Don't auto-expand while typing - let them finish
                // Only expand on blur or when they select from picker
            }
        } else {
            resolvedParkName = nil
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ParkEntryField(
            parkReference: .constant("US-1234"),
            userGrid: "FN31pr"
        )
        ParkEntryField(
            parkReference: .constant(""),
            userGrid: nil
        )
    }
    .padding()
}
```

### Step 2: Commit

```bash
git add CarrierWave/Views/Logger/ParkEntryField.swift
git commit -m "feat: add ParkEntryField with shorthand and picker"
```

---

## Task 4: Update SessionStartSheet to Use New Park Entry

**Files:**
- Modify: `CarrierWave/Views/Logger/SessionStartSheet.swift`

**Goal:** Replace the simple park TextField with the new ParkEntryField component.

### Step 1: Update ActivationSectionView to use ParkEntryField

In `SessionStartSheet.swift`, update the `ActivationSectionView`:

```swift
// MARK: - ActivationSectionView

/// Extracted view for activation type selection
struct ActivationSectionView: View {
    @Binding var activationType: ActivationType
    @Binding var parkReference: String
    @Binding var sotaReference: String
    
    /// User's grid square for nearby parks
    var userGrid: String?
    /// Default country prefix for park shorthand
    var defaultCountry: String = "US"

    var body: some View {
        Section("Activation Type") {
            Picker("Type", selection: $activationType) {
                ForEach(ActivationType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            if activationType == .pota {
                ParkEntryField(
                    parkReference: $parkReference,
                    label: "Park",
                    placeholder: "1234 or US-1234",
                    userGrid: userGrid,
                    defaultCountry: defaultCountry
                )
            }

            if activationType == .sota {
                HStack {
                    Text("Summit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("W4C/CM-001", text: $sotaReference)
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.monospaced())
                }
            }
        }
    }
}
```

### Step 2: Pass userGrid to ActivationSectionView

Update the `activationSection` computed property in SessionStartSheet:

```swift
private var activationSection: some View {
    ActivationSectionView(
        activationType: $activationType,
        parkReference: $parkReference,
        sotaReference: $sotaReference,
        userGrid: myGrid.isEmpty ? defaultGrid : myGrid,
        defaultCountry: inferredCountry
    )
}

/// Infer country from user's grid or default to US
private var inferredCountry: String {
    // Could enhance this to detect country from grid
    // For now, default to US
    "US"
}
```

### Step 3: Commit

```bash
git add CarrierWave/Views/Logger/SessionStartSheet.swift
git commit -m "feat: use ParkEntryField in session start sheet"
```

---

## Task 5: Add State Entry Field to Logger

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Goal:** Add a State entry field in the always-visible and more-fields sections.

### Step 1: Add state field state variable and AppStorage

Add to LoggerView's properties (near line 230):

```swift
// Always visible field settings (add theirState)
@AppStorage("loggerShowTheirState") private var showTheirStateAlways = false

// Input fields (add theirState)
@State private var theirState = ""
```

### Step 2: Update hasAlwaysVisibleFields and hasMoreFields

```swift
/// Whether any fields are configured to always be visible
private var hasAlwaysVisibleFields: Bool {
    showNotesAlways || showTheirGridAlways || showTheirParkAlways || 
    showOperatorAlways || showTheirStateAlways
}

/// Whether there are any fields left to show in "More Fields"
private var hasMoreFields: Bool {
    !showNotesAlways || !showTheirGridAlways || !showTheirParkAlways || 
    !showOperatorAlways || !showTheirStateAlways
}
```

### Step 3: Create theirStateField computed property

Add near the other field views (around line 580):

```swift
private var theirStateField: some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("State")
            .font(.caption)
            .foregroundStyle(.secondary)
        TextField(lookupResult?.state ?? "ST", text: $theirState)
            .font(.subheadline.monospaced())
            .textInputAutocapitalization(.characters)
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 60)
    }
}
```

### Step 4: Add State field to alwaysVisibleFieldsSection

Update the `alwaysVisibleFieldsSection` to include State alongside Grid:

```swift
@ViewBuilder
private var alwaysVisibleFieldsSection: some View {
    if hasAlwaysVisibleFields {
        VStack(spacing: 12) {
            // State, Grid and Park in a row if any visible
            if showTheirStateAlways || showTheirGridAlways || showTheirParkAlways {
                HStack(spacing: 12) {
                    if showTheirStateAlways {
                        theirStateField
                    }
                    if showTheirGridAlways {
                        theirGridField
                    }
                    if showTheirParkAlways {
                        theirParkField
                    }
                }
            }

            if showOperatorAlways {
                operatorField
            }

            if showNotesAlways {
                notesField
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

### Step 5: Add State field to moreFieldsSection

```swift
private var moreFieldsSection: some View {
    VStack(spacing: 12) {
        // State, Grid and Park in a row (only if not always visible)
        if !showTheirStateAlways || !showTheirGridAlways || !showTheirParkAlways {
            HStack(spacing: 12) {
                if !showTheirStateAlways {
                    theirStateField
                }
                if !showTheirGridAlways {
                    theirGridField
                }
                if !showTheirParkAlways {
                    theirParkField
                }
            }
        }

        if !showOperatorAlways {
            operatorField
        }

        if !showNotesAlways {
            notesField
        }
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
}
```

### Step 6: Update logQSO to use theirState

In the `logQSO()` function, update to pass the state:

```swift
private func logQSO() {
    guard canLog else { return }

    // Use manually entered values, or fall back to callsign lookup
    let gridToUse: String? = if !theirGrid.isEmpty { theirGrid } else { lookupResult?.grid }
    let stateToUse: String? = if !theirState.isEmpty { theirState } else { lookupResult?.state }

    _ = sessionManager?.logQSO(
        callsign: callsignInput,
        rstSent: rstSent.isEmpty ? defaultRST : rstSent,
        rstReceived: rstReceived.isEmpty ? defaultRST : rstReceived,
        theirGrid: gridToUse,
        theirParkReference: theirPark.isEmpty ? nil : theirPark,
        notes: notes.isEmpty ? nil : notes,
        name: lookupResult?.name,
        operatorName: operatorName.isEmpty ? lookupResult?.displayName : operatorName,
        state: stateToUse,  // Use our override
        country: lookupResult?.country,
        qth: lookupResult?.qth,
        theirLicenseClass: lookupResult?.licenseClass
    )
    
    // ... rest of reset logic, add theirState reset:
    theirState = ""
}
```

### Step 7: Add toggle in Settings

Note: The toggle for `loggerShowTheirState` should be added to SettingsView in the Logger settings section. This is a follow-up task.

### Step 8: Commit

```bash
git add CarrierWave/Views/Logger/LoggerView.swift
git commit -m "feat: add State entry field to logger"
```

---

## Task 6: Reorganize Notes and RST Field Layout

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Goal:** Move Notes field below Callsign row, make RST fields smaller and position next to Notes area.

### Step 1: Create new combined notes/RST row section

Add a new computed property for the combined row:

```swift
/// Notes field with compact RST fields beside it
private var notesAndRSTSection: some View {
    HStack(alignment: .top, spacing: 12) {
        // Notes field (expandable)
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Notes...", text: $notes, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1 ... 3)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        // Compact RST fields
        VStack(spacing: 8) {
            VStack(alignment: .center, spacing: 2) {
                Text("Sent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField(defaultRST, text: $rstSent)
                    .font(.subheadline.monospaced())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 55)
            }

            VStack(alignment: .center, spacing: 2) {
                Text("Rcvd")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField(defaultRST, text: $rstReceived)
                    .font(.subheadline.monospaced())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 55)
            }
        }
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
}
```

### Step 2: Update body to use new layout

Update the ScrollView content in the body to reorder sections:

```swift
ScrollView {
    VStack(spacing: 12) {
        UnderConstructionBanner()

        // Only show QSO form when session is active
        if sessionManager?.hasActiveSession == true {
            callsignInputSection

            // POTA duplicate/new band warning
            if let status = potaDuplicateStatus {
                POTAStatusBanner(status: status)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }

            // Show callsign info or error when keyboard is not visible
            callsignLookupDisplay

            // Notes with compact RST beside it (new layout)
            notesAndRSTSection

            // Additional fields section (State, Grid, Park, Operator)
            additionalFieldsSection

            if showMoreFields, hasMoreFields {
                moreFieldsSection
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }

            logButtonSection
        }

        qsoListSection
    }
    .padding()
}
```

### Step 3: Create additionalFieldsSection

This section contains State, Grid, Park, Operator when configured as always visible:

```swift
@ViewBuilder
private var additionalFieldsSection: some View {
    let hasVisibleFields = showTheirStateAlways || showTheirGridAlways || 
                           showTheirParkAlways || showOperatorAlways
    
    if hasVisibleFields {
        VStack(spacing: 12) {
            // State, Grid, Park row
            if showTheirStateAlways || showTheirGridAlways || showTheirParkAlways {
                HStack(spacing: 12) {
                    if showTheirStateAlways {
                        theirStateField
                    }
                    if showTheirGridAlways {
                        theirGridField
                    }
                    if showTheirParkAlways {
                        theirParkFieldEnhanced
                    }
                }
            }

            if showOperatorAlways {
                operatorField
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Enhanced their park field using the new ParkEntryField
private var theirParkFieldEnhanced: some View {
    ParkEntryField(
        parkReference: $theirPark,
        label: "Their Park",
        placeholder: "K-1234",
        userGrid: nil,  // Don't need nearby for their park
        defaultCountry: "US"
    )
}
```

### Step 4: Remove old qsoFormSection

The old `qsoFormSection` (which had RST and More button) should be removed since RST is now in `notesAndRSTSection`. Keep the More button logic but move it:

```swift
/// More/Less toggle button
@ViewBuilder
private var moreFieldsToggle: some View {
    if hasMoreFields {
        Button {
            withAnimation {
                showMoreFields.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showMoreFields ? "chevron.up" : "chevron.down")
                Text(showMoreFields ? "Less" : "More Fields")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
```

Add this toggle below the additionalFieldsSection in the body.

### Step 5: Update moreFieldsSection to not include Notes (it's always visible now)

```swift
private var moreFieldsSection: some View {
    VStack(spacing: 12) {
        // State, Grid and Park (only if not always visible)
        if !showTheirStateAlways || !showTheirGridAlways || !showTheirParkAlways {
            HStack(spacing: 12) {
                if !showTheirStateAlways {
                    theirStateField
                }
                if !showTheirGridAlways {
                    theirGridField
                }
                if !showTheirParkAlways {
                    theirParkFieldEnhanced
                }
            }
        }

        if !showOperatorAlways {
            operatorField
        }
    }
    .padding()
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
}
```

### Step 6: Remove showNotesAlways since Notes is always visible

Remove the `@AppStorage("loggerShowNotes")` and update `hasAlwaysVisibleFields` / `hasMoreFields`:

```swift
// Remove this line:
// @AppStorage("loggerShowNotes") private var showNotesAlways = false

/// Whether any fields are configured to always be visible
private var hasAlwaysVisibleFields: Bool {
    showTheirStateAlways || showTheirGridAlways || showTheirParkAlways || showOperatorAlways
}

/// Whether there are any fields left to show in "More Fields"
private var hasMoreFields: Bool {
    !showTheirStateAlways || !showTheirGridAlways || !showTheirParkAlways || !showOperatorAlways
}
```

### Step 7: Commit

```bash
git add CarrierWave/Views/Logger/LoggerView.swift
git commit -m "feat: reorganize logger with Notes+RST row, add State field"
```

---

## Task 7: Update File Index

**Files:**
- Modify: `docs/FILE_INDEX.md`

**Goal:** Add the new files to the file index.

### Step 1: Add new files to Logger section

Add to the `Views - Logger` section:

```markdown
| `ParkPickerSheet.swift` | Park search and nearby selection sheet |
| `ParkEntryField.swift` | Enhanced park entry with search/shorthand |
```

### Step 2: Commit

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: add new logger files to file index"
```

---

## Task 8: Update Changelog

**Files:**
- Modify: `CHANGELOG.md`

**Goal:** Document the new features.

### Step 1: Add entries to Unreleased section

```markdown
## [Unreleased]

### Added
- Park entry now supports searching by name with picker sheet
- Nearby parks list based on user's grid square location
- Park number shorthand: type "1234" to auto-expand to "US-1234" (based on QTH)
- State entry field in QSO logger for manual state override
- Notes field is now always visible below callsign with compact RST fields beside it
```

### Step 2: Commit

```bash
git add CHANGELOG.md
git commit -m "docs: add logger improvements to changelog"
```

---

## Summary

This plan implements 6 logger improvements:

1. **Park name search** - Extended POTAParksCache with full-text search capability
2. **Nearby parks** - Added geospatial query using haversine distance from user's grid
3. **Park number shorthand** - Type "1234" → "US-1234" based on inferred country
4. **State field** - New entry field for manual state override
5. **Notes repositioning** - Notes always visible below callsign
6. **RST compacting** - Smaller RST fields positioned beside Notes

Total new files: 2 (`ParkPickerSheet.swift`, `ParkEntryField.swift`)
Modified files: 4 (`POTAParksCache.swift`, `SessionStartSheet.swift`, `LoggerView.swift`, `FILE_INDEX.md`, `CHANGELOG.md`)
