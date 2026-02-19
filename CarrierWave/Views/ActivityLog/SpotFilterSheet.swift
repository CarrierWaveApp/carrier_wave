import SwiftUI

// MARK: - SpotFilters

/// Filter state for the activity log spot list.
/// Persisted via @AppStorage.
struct SpotFilters: Equatable {
    enum SourceFilter: String, CaseIterable {
        case pota = "POTA"
        case rbn = "RBN"

        // MARK: Internal

        var label: String {
            rawValue
        }
    }

    enum ProximityMode: String, CaseIterable {
        case heardNearby = "Heard Nearby"
        case all = "All Spots"
    }

    /// Selected source filters (empty = show all, default: POTA)
    var sources: Set<SourceFilter> = [.pota]

    /// Selected band filters (empty = show all, default: 20m)
    var bands: Set<String> = ["20m"]

    /// Selected mode filters (empty = show all, default: CW)
    var modes: Set<String> = ["CW"]

    /// Whether to hide already-worked callsigns
    var hideWorked = false

    /// Proximity filter mode
    var proximityMode: ProximityMode = .heardNearby

    /// Whether any filters are active
    var hasActiveFilters: Bool {
        !sources.isEmpty || !bands.isEmpty || !modes.isEmpty
            || hideWorked || proximityMode == .heardNearby
    }

    /// Apply all filters to a spot list
    func apply(
        to spots: [EnrichedSpot],
        workedResults: [String: WorkedBeforeResult],
        maxAgeMinutes: Int,
        proximityRadiusMiles: Int
    ) -> [EnrichedSpot] {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeMinutes) * 60)
        let radiusMeters = Double(proximityRadiusMiles) * 1_609.344

        return spots.filter { spot in
            if spot.spot.timestamp < cutoff {
                return false
            }

            if !sources.isEmpty {
                let spotSource: SourceFilter = spot.spot.source == .pota ? .pota : .rbn
                if !sources.contains(spotSource) {
                    return false
                }
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

            if proximityMode == .heardNearby {
                if let distance = spot.distanceMeters, distance > radiusMeters {
                    return false
                }
            }

            return true
        }
    }
}

// MARK: - SpotFilterSheet

/// Full filter sheet with source, band, mode, and toggle options.
struct SpotFilterSheet: View {
    // MARK: Internal

    @Binding var filters: SpotFilters

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                proximitySection
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
                    if filters != SpotFilters() {
                        Button("Reset") {
                            filters = SpotFilters()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private let commonBands = ["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"]
    private let commonModes = ["CW", "SSB", "FT8", "FT4", "RTTY"]

    private var proximitySection: some View {
        Section("Proximity") {
            Picker("Show", selection: $filters.proximityMode) {
                ForEach(SpotFilters.ProximityMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            ForEach(SpotFilters.SourceFilter.allCases, id: \.self) { source in
                Toggle(source.label, isOn: Binding(
                    get: { filters.sources.contains(source) },
                    set: { isOn in
                        if isOn {
                            filters.sources.insert(source)
                        } else {
                            filters.sources.remove(source)
                        }
                    }
                ))
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
