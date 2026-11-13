# Club Integration Enhancements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Surface club membership prominently across spot lists, filters, and session summaries — grouping club members first with section headers, adding a club filter chip, and showing a session club summary card.

**Architecture:** All features use the existing `ClubsSyncService.shared` singleton (O(1) in-memory `clubsByCallsign` map). No model or persistence changes needed. Changes are purely view-layer: partitioning spot arrays, adding section headers, and wiring a filter toggle.

**Tech Stack:** SwiftUI, SwiftData (read-only via existing service)

**Note:** The QSO logging badge (design item 5) already exists at `LoggerView+FormFields.swift:82-100` — it shows the club icon and club names when the callsign matches. No work needed.

---

### Task 1: Add `clubOnly` filter to SpotFilters

**Files:**
- Modify: `CarrierWave/Views/ActivityLog/SpotFilterSheet.swift:7-125` (SpotFilters struct + CodableStorage + SpotFilterSheet)
- Modify: `CarrierWave/Views/ActivityLog/SpotFilterBar.swift:15-25` (chip rendering)

**Step 1: Add `clubOnly` field to `SpotFilters` struct**

In `SpotFilterSheet.swift`, add the field to `SpotFilters` (after line 31):

```swift
/// Whether to show only club member spots
var clubOnly = false
```

Update `hasActiveFilters` (line 34) to include it:

```swift
var hasActiveFilters: Bool {
    !sources.isEmpty || !bands.isEmpty || !modes.isEmpty || hideWorked || clubOnly
}
```

**Step 2: Update `CodableStorage` for backward-compatible persistence**

Replace the `CodableStorage` struct (lines 95-100) with a version that handles missing `clubOnly` in old stored data:

```swift
private struct CodableStorage: Codable {
    let sources: Set<SourceFilter>
    let bands: Set<String>
    let modes: Set<String>
    let hideWorked: Bool
    let clubOnly: Bool

    init(
        sources: Set<SourceFilter>,
        bands: Set<String>,
        modes: Set<String>,
        hideWorked: Bool,
        clubOnly: Bool
    ) {
        self.sources = sources
        self.bands = bands
        self.modes = modes
        self.hideWorked = hideWorked
        self.clubOnly = clubOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decode(Set<SourceFilter>.self, forKey: .sources)
        bands = try container.decode(Set<String>.self, forKey: .bands)
        modes = try container.decode(Set<String>.self, forKey: .modes)
        hideWorked = try container.decode(Bool.self, forKey: .hideWorked)
        clubOnly = try container.decodeIfPresent(Bool.self, forKey: .clubOnly) ?? false
    }
}
```

Update `init?(rawValue:)` (line 111) to read `clubOnly`:

```swift
clubOnly = storage.clubOnly
```

Update `rawValue` getter (lines 115-116) to write it:

```swift
let storage = CodableStorage(
    sources: sources, bands: bands, modes: modes,
    hideWorked: hideWorked, clubOnly: clubOnly
)
```

**Step 3: Add club toggle to SpotFilterSheet**

In the `togglesSection` (line 276-279), add a club toggle:

```swift
private var togglesSection: some View {
    Section {
        Toggle("Hide Already Worked", isOn: $filters.hideWorked)
        if !ClubsSyncService.shared.clubMemberCallsigns.isEmpty {
            Toggle("Club Members Only", isOn: $filters.clubOnly)
        }
    }
}
```

**Step 4: Add club chip to SpotFilterBar**

In `SpotFilterBar.swift`, add a club chip after the `hideWorked` chip (after line 24):

```swift
if filters.clubOnly {
    activeChip(label: "Club Only") {
        filters.clubOnly = false
    }
}
```

**Step 5: Build and verify**

Run: `xc build`
Expected: Clean build

**Step 6: Commit**

```
feat: add clubOnly filter to SpotFilters with chip and sheet toggle (CAR-XXX)
```

---

### Task 2: Hunter log — club-first grouping with section headers

**Files:**
- Modify: `CarrierWave/Views/ActivityLog/ActivityLogSpotsList.swift:160-300`
- Modify: `CarrierWave/Views/ActivityLog/ActivityLogSpotRow.swift:70-123`

**Step 1: Add club name display to ActivityLogSpotRow**

In `ActivityLogSpotRow.swift`, replace the existing club icon block (lines 106-112) with a labeled badge showing club names:

```swift
let clubNames = ClubsSyncService.shared.clubs(for: spot.spot.callsign)
if !clubNames.isEmpty {
    HStack(spacing: 2) {
        Image(systemName: "person.3.fill")
            .font(.caption2)
        Text(clubNames.joined(separator: ", "))
            .font(.caption2)
            .lineLimit(1)
    }
    .foregroundStyle(.blue)
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(Color.blue.opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 3))
}
```

**Step 2: Add club filtering and partitioning to ActivityLogSpotsList**

In `ActivityLogSpotsList.swift`, add a computed property after `sortedSpots` (after line 180):

```swift
/// Spots after applying the club-only filter
private var clubFilteredSpots: [EnrichedSpot] {
    if filters.clubOnly {
        return sortedSpots.filter {
            !ClubsSyncService.shared.clubs(for: $0.spot.callsign).isEmpty
        }
    }
    return sortedSpots
}

/// Club member spots (only when not in club-only mode, to avoid redundant header)
private var clubMemberSpots: [EnrichedSpot] {
    guard !filters.clubOnly else { return [] }
    return clubFilteredSpots.filter {
        !ClubsSyncService.shared.clubs(for: $0.spot.callsign).isEmpty
    }
}

/// Non-club-member spots
private var otherSpots: [EnrichedSpot] {
    guard !filters.clubOnly else { return clubFilteredSpots }
    return clubFilteredSpots.filter {
        ClubsSyncService.shared.clubs(for: $0.spot.callsign).isEmpty
    }
}
```

**Step 3: Update spotContent to render sections**

Replace `spotContent` (lines 260-279) to use the club-first partitioning:

```swift
private var spotContent: some View {
    let allVisible = filters.clubOnly ? clubFilteredSpots : clubFilteredSpots
    let visible = showAll ? allVisible : Array(allVisible.prefix(Self.visibleLimit))
    let hasMore = !showAll && allVisible.count > Self.visibleLimit

    return LazyVStack(spacing: 0) {
        if !clubMemberSpots.isEmpty {
            clubSectionHeader("Club Members")
            let clubVisible = showAll
                ? clubMemberSpots
                : Array(clubMemberSpots.prefix(Self.visibleLimit))
            spotRows(clubVisible)

            if !otherSpots.isEmpty {
                clubSectionHeader("Other Spots")
            }
        }

        let otherVisible: [EnrichedSpot]
        if clubMemberSpots.isEmpty {
            // No club members — show all without headers
            otherVisible = showAll
                ? clubFilteredSpots
                : Array(clubFilteredSpots.prefix(Self.visibleLimit))
        } else {
            let remaining = Self.visibleLimit - clubMemberSpots.count
            otherVisible = showAll
                ? otherSpots
                : Array(otherSpots.prefix(max(remaining, 0)))
        }
        spotRows(otherVisible)

        if hasMore {
            Button {
                showAll = true
            } label: {
                Text("Show \(allVisible.count - Self.visibleLimit) More")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }
}
```

**Step 4: Add section header helper**

Add a helper view below `spotContent`:

```swift
private func clubSectionHeader(_ title: String) -> some View {
    HStack {
        if title == "Club Members" {
            Image(systemName: "person.3.fill")
                .font(.caption)
                .foregroundStyle(.blue)
        }
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color(.secondarySystemGroupedBackground))
}
```

**Step 5: Update spot count in header**

In `spotsHeader` (line 189), update the count to use `clubFilteredSpots`:

```swift
Text("\(clubFilteredSpots.count)")
```

**Step 6: Build and verify**

Run: `xc build`
Expected: Clean build

**Step 7: Commit**

```
feat: group hunter log spots by club membership with section headers (CAR-XXX)
```

---

### Task 3: POTA spots — club section above bands

**Files:**
- Modify: `CarrierWave/Views/Logger/POTASpotsView.swift:84-261`
- Modify: `CarrierWave/Views/Logger/SidebarPOTASpotsView.swift:81-237`
- Modify: `CarrierWave/Views/Logger/POTASpotRow.swift:128-134`

**Step 1: Add club name display to POTASpotRow**

In `POTASpotRow.swift`, replace the existing club icon (lines 128-134) with a labeled badge (same pattern as ActivityLogSpotRow):

```swift
let clubNames = ClubsSyncService.shared.clubs(for: spot.activator)
if !clubNames.isEmpty {
    HStack(spacing: 2) {
        Image(systemName: "person.3.fill")
            .font(.caption2)
        Text(clubNames.joined(separator: ", "))
            .font(.caption2)
            .lineLimit(1)
    }
    .foregroundStyle(.blue)
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(Color.blue.opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 3))
}
```

**Step 2: Add club partition computed properties to POTASpotsView**

In `POTASpotsView.swift`, after `spotsByBand` (line 122), add:

```swift
private var clubPOTASpots: [POTASpot] {
    filteredSpots.filter {
        !ClubsSyncService.shared.clubs(for: $0.activator).isEmpty
    }
}

private var clubSOTASpots: [SOTASpot] {
    filteredSOTASpots.filter {
        !ClubsSyncService.shared.clubs(for: $0.activatorCallsign).isEmpty
    }
}

private var hasClubSpots: Bool {
    !clubPOTASpots.isEmpty || !clubSOTASpots.isEmpty
}

/// POTA spots with club members removed (for band grouping)
private var nonClubPOTASpots: [POTASpot] {
    guard hasClubSpots else { return filteredSpots }
    let clubCallsigns = Set(clubPOTASpots.map { $0.activator.uppercased() })
    return filteredSpots.filter { !clubCallsigns.contains($0.activator.uppercased()) }
}

private var nonClubSOTASpots: [SOTASpot] {
    guard hasClubSpots else { return filteredSOTASpots }
    let clubCallsigns = Set(clubSOTASpots.map { $0.activatorCallsign.uppercased() })
    return filteredSOTASpots.filter {
        !clubCallsigns.contains($0.activatorCallsign.uppercased())
    }
}

private var nonClubSpotsByBand: [(band: String, spots: [POTASpot])] {
    Self.groupSpotsByBand(nonClubPOTASpots)
}

private var nonClubSOTAByBand: [(band: String, spots: [SOTASpot])] {
    Self.groupSOTASpotsByBand(nonClubSOTASpots)
}
```

**Step 3: Update spotsList to render club section first**

Replace `spotsList` (lines 204-212):

```swift
private var spotsList: some View {
    ScrollView {
        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
            if hasClubSpots {
                clubSpotsSection
            }
            nonClubPotaSpotsSection
            nonClubSotaSpotsSection
        }
    }
    .frame(maxHeight: 400)
}
```

**Step 4: Add club spots section**

Add new views:

```swift
@ViewBuilder
private var clubSpotsSection: some View {
    Section {
        ForEach(clubPOTASpots) { spot in
            let result = workedResults[spot.activator.uppercased()] ?? .notWorked
            POTASpotRow(
                spot: spot,
                userCallsign: userCallsign,
                friendCallsigns: friendCallsigns,
                workedResult: result
            ) {
                onSelectSpot?(spot)
            }
            Divider().padding(.leading, 92)
        }
        ForEach(clubSOTASpots) { spot in
            let callKey = spot.activatorCallsign.uppercased()
            let result = workedResults[callKey] ?? .notWorked
            SOTASpotRow(
                spot: spot,
                friendCallsigns: friendCallsigns,
                workedResult: result
            ) {}
            Divider().padding(.leading, 92)
        }
    } header: {
        ClubSpotsSectionHeader()
    }
}

private var nonClubPotaSpotsSection: some View {
    ForEach(nonClubSpotsByBand, id: \.band) { section in
        Section {
            ForEach(section.spots) { spot in
                let result = workedResults[spot.activator.uppercased()] ?? .notWorked
                POTASpotRow(
                    spot: spot,
                    userCallsign: userCallsign,
                    friendCallsigns: friendCallsigns,
                    workedResult: result
                ) {
                    onSelectSpot?(spot)
                }
                .opacity(spot.isAutomatedSpot ? 0.7 : 1.0)
                Divider().padding(.leading, 92)
            }
        } header: {
            POTASpotsBandHeader(band: section.band)
        }
    }
}

@ViewBuilder
private var nonClubSotaSpotsSection: some View {
    if !nonClubSOTASpots.isEmpty {
        ForEach(nonClubSOTAByBand, id: \.band) { section in
            Section {
                ForEach(section.spots) { spot in
                    let callKey = spot.activatorCallsign.uppercased()
                    let result = workedResults[callKey] ?? .notWorked
                    SOTASpotRow(
                        spot: spot,
                        friendCallsigns: friendCallsigns,
                        workedResult: result
                    ) {}
                    Divider().padding(.leading, 92)
                }
            } header: {
                SOTASpotsBandHeader(band: section.band)
            }
        }
    }
}
```

**Step 5: Create shared ClubSpotsSectionHeader**

Create a new file `CarrierWave/Views/Shared/ClubSpotsSectionHeader.swift`:

```swift
import SwiftUI

/// Sticky section header for club member spots, used in POTA/SOTA/hunter log lists.
struct ClubSpotsSectionHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.3.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("Club Members")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }
}
```

**Step 6: Apply identical changes to SidebarPOTASpotsView**

Mirror the same partition properties and section structure from POTASpotsView into SidebarPOTASpotsView. The only difference: no `.frame(maxHeight: 400)` on `spotsList`, and methods are instance (not `static`).

Key changes in `SidebarPOTASpotsView.swift`:
- Add `clubPOTASpots`, `clubSOTASpots`, `hasClubSpots`, `nonClubPOTASpots`, `nonClubSOTASpots`, `nonClubSpotsByBand`, `nonClubSOTAByBand` computed properties (same logic, using instance `groupSpotsByBand`/`groupSOTASpotsByBand`)
- Replace `spotsList` to render `clubSpotsSection` + `nonClubPotaSpotsSection` + `nonClubSotaSpotsSection`
- Add `clubSpotsSection`, `nonClubPotaSpotsSection`, `nonClubSotaSpotsSection` views (identical to POTASpotsView versions, except `onSelectSpot` is non-optional)

**Step 7: Build and verify**

Run: `xc build`
Expected: Clean build

**Step 8: Commit**

```
feat: add club members section above band groups in POTA/SOTA spot views (CAR-XXX)
```

---

### Task 4: Session spots — club-first grouping

**Files:**
- Modify: `CarrierWave/Views/Sessions/SessionSpotsSection.swift:33-101`
- Modify: `CarrierWave/Views/Sessions/SessionSpotsSummaryRow.swift:87-101` (expanded content)

**Step 1: Add club name display to SessionSpotRow**

In `SessionSpotsSection.swift`, add a club badge to `SessionSpotRow.mainRow` (around line 228, in the `HStack`). After the `displayCallsign` Text and before `Spacer()`:

```swift
let clubNames = ClubsSyncService.shared.clubs(for: spot.callsign)
if !clubNames.isEmpty {
    HStack(spacing: 2) {
        Image(systemName: "person.3.fill")
            .font(.caption2)
        Text(clubNames.joined(separator: ", "))
            .font(.caption2)
            .lineLimit(1)
    }
    .foregroundStyle(.blue)
}
```

**Step 2: Partition session spots by club membership**

In `SessionSpotsSection.swift`, add computed properties:

```swift
private var clubSpots: [SessionSpot] {
    spots.filter { !ClubsSyncService.shared.clubs(for: $0.callsign).isEmpty }
}

private var nonClubSpots: [SessionSpot] {
    spots.filter { ClubsSyncService.shared.clubs(for: $0.callsign).isEmpty }
}
```

**Step 3: Update body to render club section first**

Replace the `DisclosureGroup` content (lines 36-51) to partition into club/other sections:

```swift
DisclosureGroup(isExpanded: $isSectionExpanded) {
    if !clubSpots.isEmpty {
        HStack(spacing: 4) {
            Image(systemName: "person.3.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("Club Members")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)

        ForEach(clubSpots) { spot in
            SessionSpotRow(
                spot: spot,
                isPOTAHighlight: spot.isPOTA,
                isLogged: spotQSOMatch?.spotWasLogged(spot)
            )
        }

        if !nonClubSpots.isEmpty {
            Text("Other Spots")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    // Non-club spots with RBN run collapsing
    let nonClubGroups = buildSpotGroups(from: nonClubSpots)
    ForEach(nonClubGroups) { group in
        switch group {
        case let .human(spot):
            SessionSpotRow(
                spot: spot,
                isPOTAHighlight: spot.isPOTA,
                isLogged: spotQSOMatch?.spotWasLogged(spot)
            )
        case let .rbnRun(_, rbnSpots):
            RBNRunRow(spots: rbnSpots)
        }
    }
} label: {
    Text(sectionTitle)
}
```

**Step 4: Extract spotGroups logic into a method**

Rename the existing `spotGroups` computed var to a function that takes a spot array:

```swift
private func buildSpotGroups(from spotList: [SessionSpot]) -> [SpotGroup] {
    let sorted = spotList.sorted { $0.timestamp > $1.timestamp }
    var groups: [SpotGroup] = []
    var currentRBNRun: [SessionSpot] = []

    for spot in sorted {
        if spot.isRBN {
            currentRBNRun.append(spot)
        } else {
            if !currentRBNRun.isEmpty {
                groups.append(.rbnRun(id: currentRBNRun[0].id, spots: currentRBNRun))
                currentRBNRun = []
            }
            groups.append(.human(spot))
        }
    }
    if !currentRBNRun.isEmpty {
        groups.append(.rbnRun(id: currentRBNRun[0].id, spots: currentRBNRun))
    }
    return groups
}
```

**Step 5: Build and verify**

Run: `xc build`
Expected: Clean build

**Step 6: Commit**

```
feat: group session spots by club membership with section headers (CAR-XXX)
```

---

### Task 5: Session club summary card

**Files:**
- Modify: `CarrierWave/Views/Sessions/SessionDetailView.swift:63-123` (body)
- Modify: `CarrierWave/Views/Sessions/SessionDetailView+Components.swift` (add new section)

**Step 1: Add club summary computed properties**

In `SessionDetailView+Components.swift`, add an extension method:

```swift
/// Club members contacted during this session
var clubMemberQSOs: [(callsign: String, clubs: [String])] {
    var seen = Set<String>()
    var results: [(callsign: String, clubs: [String])] = []
    for qso in qsos {
        let key = qso.callsign.uppercased()
        guard !seen.contains(key) else { continue }
        let clubs = ClubsSyncService.shared.clubs(for: qso.callsign)
        guard !clubs.isEmpty else { continue }
        seen.insert(key)
        results.append((callsign: qso.callsign, clubs: clubs))
    }
    return results
}
```

**Step 2: Add club summary section view**

In `SessionDetailView+Components.swift`, add:

```swift
@ViewBuilder
var clubMembersSummarySection: some View {
    let members = clubMemberQSOs
    if !members.isEmpty {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You worked \(members.count) club member\(members.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                    Text(members.map(\.callsign).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            ForEach(members, id: \.callsign) { member in
                HStack {
                    Text(member.callsign)
                        .font(.subheadline.weight(.medium).monospaced())
                    Spacer()
                    Text(member.clubs.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

**Step 3: Add to SessionDetailView body**

In `SessionDetailView.swift`, add the club summary section after the rove stops section and before `mapSection` (after line 75):

```swift
clubMembersSummarySection
```

**Step 4: Build and verify**

Run: `xc build`
Expected: Clean build

**Step 5: Commit**

```
feat: add club members summary card to session detail view (CAR-XXX)
```

---

### Task 6: Final integration and quality check

**Step 1: Run full quality pipeline**

Run: `xc quality` (format + lint + build)

Fix any SwiftLint violations (file length, function length, line length).

**Step 2: Check file lengths**

Key files to check against 500-line limit:
- `ActivityLogSpotsList.swift` (was 367 lines, adding ~50)
- `POTASpotsView.swift` (was 367 lines, adding ~80 — may need to split)
- `SidebarPOTASpotsView.swift` (was 339 lines, adding ~80 — may need to split)
- `SessionSpotsSection.swift` (was 328 lines, adding ~30)

If any file exceeds 500 lines, extract the club section views into a new extension file.

**Step 3: Update FILE_INDEX.md**

Add entry for `ClubSpotsSectionHeader.swift`.

**Step 4: Update CHANGELOG.md**

```markdown
### Added
- Club members grouped first in hunter log, session spots, and POTA/SOTA spot lists with section headers
- Club name badges shown on spot rows for club members
- "Club Members Only" filter toggle in hunter log spot filters
- Club members summary card in session detail view showing which contacts were club members
```

**Step 5: Final commit**

```
chore: quality cleanup, file index, and changelog for club integration (CAR-XXX)
```
