import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - POTASpotsDisplayMode

/// Controls whether spots are shown as a modal panel or persistent sidebar
enum POTASpotsDisplayMode {
    /// Modal panel with header, dismiss button, rounded styling, height-limited list
    case panel
    /// Persistent sidebar with auto-refresh, no dismiss, full-height list
    case sidebar
}

// MARK: - POTASpotsView

/// Panel showing active POTA and SOTA spots with filtering.
/// Supports both modal panel and persistent sidebar layouts via `displayMode`.
struct POTASpotsView: View {
    // MARK: Lifecycle

    init(
        displayMode: POTASpotsDisplayMode = .panel,
        userCallsign: String? = nil,
        initialBand: String? = nil,
        initialMode: String? = nil,
        onDismiss: (() -> Void)? = nil,
        onSelectSpot: ((POTASpot) -> Void)? = nil,
        onSelectSOTASpot: ((SOTASpot) -> Void)? = nil
    ) {
        self.displayMode = displayMode
        self.userCallsign = userCallsign
        self.onDismiss = onDismiss
        self.onSelectSpot = onSelectSpot
        self.onSelectSOTASpot = onSelectSOTASpot

        // Seed band/mode sets from session context
        var bands = Set<String>()
        if let band = initialBand {
            bands.insert(band)
        }
        _selectedBands = State(initialValue: bands)

        var modes = Set<String>()
        if let mode = initialMode {
            let filter = ModeFilter.from(modeName: mode)
            if filter != .all {
                modes.insert(filter.rawValue)
            }
        }
        _selectedModes = State(initialValue: modes)
    }

    // MARK: Internal

    @State var workedResults: [String: WorkedBeforeResult] = [:]

    @Environment(\.modelContext) var modelContext

    @State var allSpots: [POTASpot] = []
    @State var allSOTASpots: [SOTASpot] = []
    @State var isLoading = true
    @State var errorMessage: String?
    @State var workedBeforeCache = WorkedBeforeCache()

    @AppStorage("huntShowClubSection") var showClubSection = true
    @AppStorage("huntClubFilter") var clubFilterRaw = ""
    @AppStorage("huntShowFriends") var showFriends = true

    let displayMode: POTASpotsDisplayMode
    let userCallsign: String?
    let onDismiss: (() -> Void)?
    let onSelectSpot: ((POTASpot) -> Void)?
    let onSelectSOTASpot: ((SOTASpot) -> Void)?

    var friendCallsigns: Set<String> {
        guard showFriends else {
            return []
        }
        return Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
    }

    var filteredSpots: [POTASpot] {
        guard showPOTA else {
            return []
        }
        return OnAirSpotFilter.filterPOTA(
            allSpots, bands: selectedBands, modes: selectedModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }

    var filteredSOTASpots: [SOTASpot] {
        guard showSOTA else {
            return []
        }
        return OnAirSpotFilter.filterSOTA(
            allSOTASpots, bands: selectedBands, modes: selectedModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }

    var body: some View {
        content
            .task {
                await loadSpots()
            }
            .task(id: displayMode == .sidebar ? "auto-refresh" : "none") {
                guard displayMode == .sidebar else {
                    return
                }
                await autoRefreshLoop()
            }
    }

    // MARK: Private

    @AppStorage("huntSpotMaxAgeMinutes") private var spotMaxAgeMinutes = 30
    @AppStorage("huntShowPOTA") private var showPOTA = true
    @AppStorage("huntShowSOTA") private var showSOTA = true
    @State private var selectedBands: Set<String>
    @State private var selectedModes: Set<String>
    @State private var showFilterSheet = false

    private var acceptedFriends: [Friendship] {
        FriendsSyncService.shared.acceptedFriends
    }

    private var isPanel: Bool {
        displayMode == .panel
    }

    private var sotaSpotsByBand: [(band: String, spots: [SOTASpot])] {
        Self.groupSOTASpotsByBand(filteredSOTASpots)
    }

    private var spotsByBand: [(band: String, spots: [POTASpot])] {
        Self.groupSpotsByBand(filteredSpots)
    }

    private var hasActiveFilters: Bool {
        !showPOTA || !showSOTA
            || !selectedBands.isEmpty || !selectedModes.isEmpty
            || !showClubSection || !clubFilterRaw.isEmpty
            || !showFriends
    }

    private var filterDisplayText: String {
        guard hasActiveFilters else {
            return "All Spots"
        }
        var parts: [String] = []
        if !showPOTA {
            parts.append("SOTA only")
        } else if !showSOTA {
            parts.append("POTA only")
        }
        if !selectedBands.isEmpty {
            parts.append(sortedBandNames(selectedBands))
        }
        if !selectedModes.isEmpty {
            parts.append(selectedModes.sorted().joined(separator: ", "))
        }
        if !showClubSection {
            parts.append("No clubs")
        } else if !clubFilterRaw.isEmpty {
            let count = OnAirSpotFilter.decodeSet(from: clubFilterRaw).count
            parts.append("\(count) club(s)")
        }
        if !showFriends {
            parts.append("No friends")
        }
        return parts.joined(separator: " \u{2022} ")
    }

    private var filterIcon: String {
        hasActiveFilters
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        let stack = VStack(spacing: 0) {
            if isPanel {
                header
            }
            filterBar
            Divider()
            spotsContent
        }
        if isPanel {
            stack
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        } else {
            stack
        }
    }

    @ViewBuilder
    private var spotsContent: some View {
        let showLoading = isPanel ? isLoading : (isLoading && allSpots.isEmpty)
        let showError = isPanel
            ? (errorMessage != nil)
            : (errorMessage != nil && allSpots.isEmpty)

        if showLoading {
            POTASpotsLoadingView()
        } else if showError {
            POTASpotsErrorView(message: errorMessage ?? "") {
                Task { await loadSpots() }
            }
        } else if filteredSpots.isEmpty, filteredSOTASpots.isEmpty {
            POTASpotsEmptyView(
                hasFilters: hasActiveFilters,
                onClearFilters: { clearAllFilters() }
            )
        } else {
            spotsList
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "binoculars")
                .foregroundStyle(.blue)
            Text("Activator Spots")
                .font(.headline)
            Spacer()
            Button {
                Task { await loadSpots() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Refresh spots")
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close")
            }
        }
        .padding()
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: filterIcon)
                        .font(.caption)
                    Text(filterDisplayText)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFilterSheet) {
                HuntFilterSheet(
                    selectedBands: $selectedBands,
                    selectedModes: $selectedModes,
                    isPresented: $showFilterSheet
                )
            }

            Spacer()

            if !isPanel, isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text("\(filteredSpots.count + filteredSOTASpots.count) spots")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(isPanel ? .bottom : .vertical, 6)
    }

    // MARK: - Content Views

    @ViewBuilder
    private var spotsList: some View {
        let scroll = ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                if hasClubSpots {
                    clubSpotsSection
                }
                nonClubPotaSpotsSection
                nonClubSotaSpotsSection
            }
        }
        if isPanel {
            scroll.frame(maxHeight: 400)
        } else {
            scroll
        }
    }

    // MARK: - Helpers

    private func clearAllFilters() {
        selectedBands = []
        selectedModes = []
    }

    private func sortedBandNames(_ bands: Set<String>) -> String {
        bands.sorted { lhs, rhs in
            let lhsNum = lhs.filter(\.isNumber)
            let rhsNum = rhs.filter(\.isNumber)
            return (Int(lhsNum) ?? 0) > (Int(rhsNum) ?? 0)
        }.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview {
    POTASpotsView(
        userCallsign: "W1AW",
        initialBand: "20m",
        initialMode: "CW",
        onDismiss: {}
    )
    .frame(height: 500)
    .padding()
}
