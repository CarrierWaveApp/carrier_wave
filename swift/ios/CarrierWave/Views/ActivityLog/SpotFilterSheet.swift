import CarrierWaveData
import SwiftUI

// MARK: - SpotFilters

/// Filter state for the activity log spot list.
/// Persisted via @AppStorage using RawRepresentable JSON encoding.
struct SpotFilters: Equatable, Codable {
    enum SourceFilter: String, CaseIterable, Codable {
        case pota = "POTA"
        case wwff = "WWFF"
        case sota = "SOTA"
        case rbn = "RBN"
        case pskr = "PSKR"
        // Engine-backed extra sources (DECIDED 2026-07-02: ship default-off;
        // absent from the default `sources` set is what keeps them off).
        case dxSummit = "DX Summit"
        case dxHeat = "DXHeat"
        case dxWatch = "DXWatch"
        case cluster = "Cluster"

        // MARK: Lifecycle

        init(source: SpotSource) {
            self = switch source {
            case .pota: .pota
            case .wwff: .wwff
            case .sota: .sota
            case .rbn: .rbn
            case .pskr: .pskr
            case .dxSummit: .dxSummit
            case .dxHeat: .dxHeat
            case .dxWatch: .dxWatch
            case .cluster: .cluster
            }
        }

        // MARK: Internal

        var label: String {
            rawValue
        }
    }

    /// Selected source filters (at least one must be selected)
    var sources: Set<SourceFilter> = [.pota, .sota]

    /// Selected band filters (empty = show all, default: 20m)
    var bands: Set<String> = ["20m"]

    /// Selected mode filters (empty = show all, default: CW)
    var modes: Set<String> = ["CW"]

    /// Whether to hide already-worked callsigns
    var hideWorked = false

    var clubOnly = false

    /// Show only spots that match operator needs
    var needsOnly = false

    /// "Filter by saved query" mode (mirrors Sweep's `bandScopeFilterMode`):
    /// when set, the engine runs this saved `.cwquery` after every publish
    /// and the snapshot's `allowed_spot_ids` becomes an extra allow-list on
    /// top of the widget filters. nil = widgets only.
    var savedQueryID: UUID?

    /// Whether any filters are active
    var hasActiveFilters: Bool {
        !sources.isEmpty || !bands.isEmpty || !modes.isEmpty || hideWorked || clubOnly
            || needsOnly || savedQueryID != nil
    }

    /// Apply all filters to a spot list. `allowedSpotIds` is the engine's
    /// saved-query allow-list; nil means no query is active (or it failed,
    /// in which case the widget filters remain authoritative).
    func apply(
        to spots: [EnrichedSpot],
        workedResults: [String: WorkedBeforeResult],
        maxAgeMinutes: Int,
        selectedContinents: Set<SpotContinent>,
        allowedSpotIds: Set<String>? = nil
    ) -> [EnrichedSpot] {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeMinutes) * 60)
        let allSelected = selectedContinents == SpotContinent.allSet
            || selectedContinents.isEmpty

        return spots.filter { spot in
            if let allowedSpotIds, !allowedSpotIds.contains(spot.spot.id) {
                return false
            }

            if spot.spot.timestamp < cutoff {
                return false
            }

            if !sources.contains(SourceFilter(source: spot.spot.source)) {
                return false
            }

            if !bands.isEmpty, !bands.contains(spot.spot.band) {
                return false
            }

            if !modes.isEmpty, !modes.contains(spot.spot.mode.uppercased()) {
                return false
            }

            if hideWorked {
                let result = workedResults[spot.spot.callsign.uppercased()]
                if let result, result.hasBeenWorked {
                    return false
                }
            }

            if !allSelected {
                if !selectedContinents.contains(spot.region.continent) {
                    return false
                }
            }

            if needsOnly, !spot.hasNeeds {
                return false
            }

            return true
        }
    }
}

// MARK: RawRepresentable

extension SpotFilters: RawRepresentable {
    /// Codable-only wrapper to avoid JSONEncoder using the RawRepresentable path
    /// (which causes infinite recursion: rawValue → encode → rawValue → ...)
    private struct CodableStorage: Codable {
        // MARK: Lifecycle

        init(
            sources: Set<SourceFilter>,
            bands: Set<String>,
            modes: Set<String>,
            hideWorked: Bool,
            clubOnly: Bool,
            needsOnly: Bool,
            savedQueryID: UUID?
        ) {
            self.sources = sources
            self.bands = bands
            self.modes = modes
            self.hideWorked = hideWorked
            self.clubOnly = clubOnly
            self.needsOnly = needsOnly
            self.savedQueryID = savedQueryID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sources = try container.decode(Set<SourceFilter>.self, forKey: .sources)
            bands = try container.decode(Set<String>.self, forKey: .bands)
            modes = try container.decode(Set<String>.self, forKey: .modes)
            hideWorked = try container.decode(Bool.self, forKey: .hideWorked)
            clubOnly = try container.decodeIfPresent(Bool.self, forKey: .clubOnly) ?? false
            needsOnly = try container.decodeIfPresent(Bool.self, forKey: .needsOnly) ?? false
            savedQueryID = try container.decodeIfPresent(UUID.self, forKey: .savedQueryID)
        }

        // MARK: Internal

        let sources: Set<SourceFilter>
        let bands: Set<String>
        let modes: Set<String>
        let hideWorked: Bool
        let clubOnly: Bool
        let needsOnly: Bool
        let savedQueryID: UUID?
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let storage = try? JSONDecoder().decode(CodableStorage.self, from: data)
        else {
            return nil
        }
        sources = storage.sources.isEmpty ? [.pota] : storage.sources
        bands = storage.bands
        modes = storage.modes
        hideWorked = storage.hideWorked
        clubOnly = storage.clubOnly
        needsOnly = storage.needsOnly
        savedQueryID = storage.savedQueryID
    }

    var rawValue: String {
        let storage = CodableStorage(
            sources: sources, bands: bands, modes: modes,
            hideWorked: hideWorked, clubOnly: clubOnly, needsOnly: needsOnly,
            savedQueryID: savedQueryID
        )
        guard let data = try? JSONEncoder().encode(storage),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

// MARK: - SpotFilterSheet

/// Full filter sheet with source, band, mode, and toggle options.
struct SpotFilterSheet: View {
    // MARK: Internal

    @Binding var filters: SpotFilters
    @Binding var selectedContinents: Set<SpotContinent>

    /// Saved `.cwquery` queries offered by the "Filter by Saved Query"
    /// section (loaded in `.task`; lives in `SpotFilterSheet+SavedQuery`).
    @State var availableSavedQueries: [SavedQuery] = []

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                savedQuerySection
                continentSection
                bandSection
                modeSection
                togglesSection
            }
            .navigationTitle("Filter Spots")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                availableSavedQueries = await loadSavedQueries()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if filters != SpotFilters()
                        || selectedContinents != SpotContinent.allSet
                    {
                        Button("Reset") {
                            filters = SpotFilters()
                            selectedContinents = SpotContinent.allSet
                        }
                    }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private let commonBands = ["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"]
    private let commonModes = ["CW", "SSB", "FT8", "FT4", "RTTY"]

    private var allContinentsSelected: Bool {
        selectedContinents == SpotContinent.allSet || selectedContinents.isEmpty
    }

    private var continentSection: some View {
        Section {
            FlowLayout(spacing: 6) {
                ForEach(SpotContinent.allCases, id: \.self) { cont in
                    filterChip(
                        label: cont.displayName,
                        isSelected: selectedContinents.contains(cont)
                    ) {
                        if selectedContinents.contains(cont) {
                            selectedContinents.remove(cont)
                            if selectedContinents.isEmpty {
                                selectedContinents = SpotContinent.allSet
                            }
                        } else {
                            selectedContinents.insert(cont)
                        }
                    }
                }
            }

            if allContinentsSelected {
                Text("All continents shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Continent")
                Spacer()
                if !allContinentsSelected {
                    Button("All") {
                        selectedContinents = SpotContinent.allSet
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            ForEach(SpotFilters.SourceFilter.allCases, id: \.self) { source in
                let isLastSelected = filters.sources.count == 1
                    && filters.sources.contains(source)
                Toggle(source.label, isOn: Binding(
                    get: { filters.sources.contains(source) },
                    set: { isOn in
                        if isOn {
                            filters.sources.insert(source)
                        } else if !isLastSelected {
                            filters.sources.remove(source)
                        }
                    }
                ))
                .disabled(isLastSelected)
            }
        }
    }

    private var bandSection: some View {
        Section("Band") {
            FlowLayout(spacing: 6) {
                ForEach(commonBands, id: \.self) { band in
                    filterChip(
                        label: band,
                        isSelected: filters.bands.contains(band)
                    ) {
                        if filters.bands.contains(band) {
                            filters.bands.remove(band)
                        } else {
                            filters.bands.insert(band)
                        }
                    }
                }
            }
        }
    }

    private var modeSection: some View {
        Section("Mode") {
            FlowLayout(spacing: 6) {
                ForEach(commonModes, id: \.self) { mode in
                    filterChip(
                        label: mode,
                        isSelected: filters.modes.contains(mode)
                    ) {
                        if filters.modes.contains(mode) {
                            filters.modes.remove(mode)
                        } else {
                            filters.modes.insert(mode)
                        }
                    }
                }
            }
        }
    }

    private var togglesSection: some View {
        Section {
            Toggle("Hide Already Worked", isOn: $filters.hideWorked)
            if !ClubsSyncService.shared.clubMemberCallsigns.isEmpty {
                Toggle("Club Members Only", isOn: $filters.clubOnly)
            }
            Toggle("Needs Only", isOn: $filters.needsOnly)
        } footer: {
            if filters.needsOnly {
                Text("Showing only spots that match your DXCC, WAS, POTA, or custom needs.")
            }
        }
    }

    private func filterChip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .background(
                    isSelected
                        ? Color.blue.opacity(0.15)
                        : Color(.tertiarySystemFill)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - FlowLayout

/// Simple flow layout for filter chips
struct FlowLayout: Layout {
    // MARK: Internal

    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? totalIdealWidth(subviews: subviews)
        let result = layout(subviews: subviews, width: maxWidth)
        return CGSize(
            width: maxWidth,
            height: result.size.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        let positions = result.positions
        for (index, position) in positions.enumerated() {
            // Cap width at the space before the next item on the same line,
            // or remaining width to the container edge if last on line.
            var proposedWidth = bounds.width - position.x
            let nextIndex = index + 1
            if nextIndex < positions.count,
               positions[nextIndex].y == position.y
            {
                proposedWidth = positions[nextIndex].x - position.x - spacing
            }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(width: proposedWidth, height: nil)
            )
        }
    }

    // MARK: Private

    private struct LayoutResult {
        var positions: [CGPoint]
        var widths: [CGFloat]
        var size: CGSize
    }

    private func totalIdealWidth(subviews: Subviews) -> CGFloat {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return widths.reduce(into: CGFloat(0)) { $0 += $1 }
            + max(0, CGFloat(subviews.count - 1)) * spacing
    }

    private func layout(subviews: Subviews, width: CGFloat) -> LayoutResult {
        var positions: [CGPoint] = []
        var widths: [CGFloat] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let idealSize = subview.sizeThatFits(.unspecified)
            let itemWidth = min(idealSize.width, width)

            if currentX + itemWidth > width, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            widths.append(itemWidth)
            lineHeight = max(lineHeight, idealSize.height)
            currentX += itemWidth + spacing
            maxWidth = max(maxWidth, min(currentX - spacing, width))
        }

        return LayoutResult(
            positions: positions,
            widths: widths,
            size: CGSize(width: maxWidth, height: currentY + lineHeight)
        )
    }
}
