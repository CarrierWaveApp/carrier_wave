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

        // MARK: Internal

        var label: String {
            rawValue
        }
    }

    /// Selected source filters (at least one must be selected)
    var sources: Set<SourceFilter> = [.pota]

    /// Selected band filters (empty = show all, default: 20m)
    var bands: Set<String> = ["20m"]

    /// Selected mode filters (empty = show all, default: CW)
    var modes: Set<String> = ["CW"]

    /// Whether to hide already-worked callsigns
    var hideWorked = false

    var clubOnly = false

    /// Whether any filters are active
    var hasActiveFilters: Bool {
        !sources.isEmpty || !bands.isEmpty || !modes.isEmpty || hideWorked || clubOnly
    }

    /// Apply all filters to a spot list
    func apply(
        to spots: [EnrichedSpot],
        workedResults: [String: WorkedBeforeResult],
        maxAgeMinutes: Int,
        selectedRegions: Set<SpotRegionGroup>
    ) -> [EnrichedSpot] {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeMinutes) * 60)
        let allSelected = selectedRegions == SpotRegionGroup.allSet
            || selectedRegions.isEmpty

        return spots.filter { spot in
            if spot.spot.timestamp < cutoff {
                return false
            }

            let spotSource: SourceFilter = switch spot.spot.source {
            case .pota: .pota
            case .wwff: .wwff
            case .sota: .sota
            case .rbn: .rbn
            }
            if !sources.contains(spotSource) {
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
                if !selectedRegions.contains(spot.region.group) {
                    return false
                }
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

        // MARK: Internal

        let sources: Set<SourceFilter>
        let bands: Set<String>
        let modes: Set<String>
        let hideWorked: Bool
        let clubOnly: Bool
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
    }

    var rawValue: String {
        let storage = CodableStorage(
            sources: sources, bands: bands, modes: modes,
            hideWorked: hideWorked, clubOnly: clubOnly
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
    @Binding var selectedRegions: Set<SpotRegionGroup>

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                regionSection
                bandSection
                modeSection
                togglesSection
            }
            .navigationTitle("Filter Spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if filters != SpotFilters()
                        || selectedRegions != SpotRegionGroup.allSet
                    {
                        Button("Reset") {
                            filters = SpotFilters()
                            selectedRegions = SpotRegionGroup.allSet
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

    private var allRegionsSelected: Bool {
        selectedRegions == SpotRegionGroup.allSet || selectedRegions.isEmpty
    }

    private var regionSection: some View {
        Section {
            FlowLayout(spacing: 6) {
                ForEach(SpotRegionGroup.allCases, id: \.self) { region in
                    filterChip(
                        label: region.rawValue,
                        isSelected: selectedRegions.contains(region)
                    ) {
                        if selectedRegions.contains(region) {
                            selectedRegions.remove(region)
                            // If removing would leave empty, select all others
                            if selectedRegions.isEmpty {
                                selectedRegions = SpotRegionGroup.allSet
                            }
                        } else {
                            selectedRegions.insert(region)
                        }
                    }
                }
            }

            if allRegionsSelected {
                Text("All regions shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Regions")
                Spacer()
                if !allRegionsSelected {
                    Button("All") {
                        selectedRegions = SpotRegionGroup.allSet
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
        let maxWidth = proposal.width ?? .infinity
        let result = layout(subviews: subviews, width: maxWidth)
        return CGSize(
            width: min(result.size.width, maxWidth),
            height: result.size.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, position) in result.positions.enumerated() {
            let remainingWidth = bounds.width - position.x
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(width: remainingWidth, height: nil)
            )
        }
    }

    // MARK: Private

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func layout(subviews: Subviews, width: CGFloat) -> LayoutResult {
        var positions: [CGPoint] = []
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
            lineHeight = max(lineHeight, idealSize.height)
            currentX += itemWidth + spacing
            maxWidth = max(maxWidth, min(currentX - spacing, width))
        }

        return LayoutResult(
            positions: positions,
            size: CGSize(width: maxWidth, height: currentY + lineHeight)
        )
    }
}
