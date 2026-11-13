import SwiftUI

// MARK: - SatelliteFilterChipLabel

/// The one capsule style every filter chip shares.
private struct SatelliteFilterChipLabel: View {
    let text: String
    let isOn: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isOn ? Color.accentColor.opacity(0.22) : Color(.systemGray5))
            .clipShape(Capsule())
    }
}

// MARK: - SatelliteBandChipRow

/// One direction's band letters as in-place toggle chips — nothing
/// dismisses, so several bands are a single gesture stream.
struct SatelliteBandChipRow: View {
    let raw: Binding<String>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SatBand.allCases) { band in
                let isOn = SatelliteModeFilter.bandSelection(from: raw.wrappedValue)
                    .contains(band)
                Button {
                    raw.wrappedValue = SatelliteModeFilter.toggledBand(
                        band, raw: raw.wrappedValue
                    )
                } label: {
                    SatelliteFilterChipLabel(text: band.label, isOn: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(band.label) \(isOn ? "on" : "off")")
            }
        }
    }
}

// MARK: - SatelliteElevationChipRow

/// Single-select minimum peak-elevation chips (Any/10°/20°/30°/45°).
struct SatelliteElevationChipRow: View {
    // MARK: Internal

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SatelliteModeFilter.peakElevationOptions, id: \.self) { option in
                Button {
                    minPeakElevation = option
                } label: {
                    SatelliteFilterChipLabel(
                        text: SatelliteModeFilter.peakElevationLabel(option),
                        isOn: minPeakElevation == option
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Passes peaking at least "
                        + SatelliteModeFilter.peakElevationLabel(option)
                )
            }
        }
    }

    // MARK: Private

    @AppStorage(SatelliteModeFilter.minPeakElevationKey) private var minPeakElevation = 0
}

// MARK: - SatelliteHorizonChipRow

/// Per-direction minimum elevation (the horizon mask): tap a sector to
/// cycle 0° → 10° → 20° → 30° → 45° → blocked. "N" = clear to the
/// horizon, "N ≥30°" = deaf below 30° that way, "N ✕" = fully blocked.
struct SatelliteHorizonChipRow: View {
    // MARK: Internal

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SkySector.allCases) { sector in
                let minimum = SatelliteModeFilter.horizonMask(from: horizonRaw)[sector] ?? 0
                Button {
                    horizonRaw = SatelliteModeFilter.cycledHorizon(sector, raw: horizonRaw)
                } label: {
                    SatelliteFilterChipLabel(
                        text: Self.label(sector: sector, minimum: minimum),
                        isOn: minimum > 0
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.accessibility(sector: sector, minimum: minimum))
            }
        }
    }

    // MARK: Private

    @AppStorage(SatelliteModeFilter.horizonMaskKey) private var horizonRaw = ""

    private static func label(sector: SkySector, minimum: Int) -> String {
        switch minimum {
        case 0:
            sector.rawValue
        case SatelliteModeFilter.blockedElevation:
            "\(sector.rawValue) ✕"
        default:
            "\(sector.rawValue) ≥\(minimum)°"
        }
    }

    private static func accessibility(sector: SkySector, minimum: Int) -> String {
        switch minimum {
        case 0:
            "\(sector.rawValue) clear to the horizon"
        case SatelliteModeFilter.blockedElevation:
            "\(sector.rawValue) fully blocked"
        default:
            "\(sector.rawValue) deaf below \(minimum) degrees"
        }
    }
}

// MARK: - SatelliteFilterToggleChips

/// The two bird-level toggles: community-heard this week, favorites only.
struct SatelliteFilterToggleChips: View {
    // MARK: Internal

    var body: some View {
        HStack(spacing: 8) {
            Button {
                heardRecentlyOnly.toggle()
            } label: {
                SatelliteFilterChipLabel(text: "Heard this week", isOn: heardRecentlyOnly)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                heardRecentlyOnly
                    ? "Showing only community-heard satellites"
                    : "Showing all satellites regardless of reports"
            )
            Button {
                favoritesOnly.toggle()
            } label: {
                SatelliteFilterChipLabel(text: "★ Favorites", isOn: favoritesOnly)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favoritesOnly ? "Showing only favorites" : "Showing all satellites")
        }
    }

    // MARK: Private

    @AppStorage(SatelliteModeFilter.heardRecentlyKey) private var heardRecentlyOnly = false
    @AppStorage(SatelliteModeFilter.favoritesOnlyKey) private var favoritesOnly = false
}

// MARK: - SatelliteBucketChipRow

/// The FM/Linear/Digital/Telemetry toggles.
struct SatelliteBucketChipRow: View {
    // MARK: Internal

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SatelliteFilterBucket.allCases) { bucket in
                let isOn = SatelliteModeFilter.selection(from: modeFilterRaw).contains(bucket)
                Button {
                    modeFilterRaw = SatelliteModeFilter.toggled(bucket, raw: modeFilterRaw)
                } label: {
                    SatelliteFilterChipLabel(text: bucket.label, isOn: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(bucket.label) satellites \(isOn ? "shown" : "hidden")")
            }
        }
    }

    // MARK: Private

    @AppStorage(SatelliteModeFilter.storageKey) private var modeFilterRaw = ""
}

// MARK: - SatelliteModeFilterChips

/// Compact filter strip for the pass-list surfaces: bucket chips plus
/// "↑/↓" expanders that reveal an inline band-letter row underneath —
/// multi-select without anything closing.
struct SatelliteModeFilterChips: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SatelliteBucketChipRow()
                    expanderChip(.uplink)
                    expanderChip(.downlink)
                    expanderChip(.elevation)
                    expanderChip(.sectors)
                    SatelliteFilterToggleChips()
                }
            }
            if let row = expandedRow {
                ScrollView(.horizontal, showsIndicators: false) {
                    switch row {
                    case .uplink:
                        SatelliteBandChipRow(raw: $uplinkRaw)
                    case .downlink:
                        SatelliteBandChipRow(raw: $downlinkRaw)
                    case .elevation:
                        SatelliteElevationChipRow()
                    case .sectors:
                        SatelliteHorizonChipRow()
                    }
                }
            }
        }
    }

    // MARK: Private

    private enum ExpandedRow {
        case uplink
        case downlink
        case elevation
        case sectors
    }

    private struct ExpanderSummary {
        let text: String
        let isNarrowed: Bool
        let accessibility: String
    }

    @AppStorage(SatelliteModeFilter.uplinkBandKey) private var uplinkRaw = ""
    @AppStorage(SatelliteModeFilter.downlinkBandKey) private var downlinkRaw = ""
    @AppStorage(SatelliteModeFilter.minPeakElevationKey) private var minPeakElevation = 0
    @AppStorage(SatelliteModeFilter.horizonMaskKey) private var sectorsRaw = ""
    /// Which secondary chip row is expanded inline, if any.
    @State private var expandedRow: ExpandedRow?

    /// "↑ All ▾" / "↓ U,V ▾" / "El ≥ 20° ▾" — tap to expand the row below.
    private func expanderChip(_ row: ExpandedRow) -> some View {
        let summary = expanderSummary(row)
        let isExpanded = expandedRow == row
        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                expandedRow = isExpanded ? nil : row
            }
        } label: {
            SatelliteFilterChipLabel(
                text: summary.text + (isExpanded ? " ▴" : " ▾"),
                isOn: summary.isNarrowed || isExpanded
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary.accessibility)
    }

    private func expanderSummary(_ row: ExpandedRow) -> ExpanderSummary {
        switch row {
        case .uplink:
            bandSummary(arrow: "↑", raw: uplinkRaw, accessibility: "Uplink band filter")
        case .downlink:
            bandSummary(arrow: "↓", raw: downlinkRaw, accessibility: "Downlink band filter")
        case .elevation:
            ExpanderSummary(
                text: "El ≥ \(SatelliteModeFilter.peakElevationLabel(minPeakElevation))",
                isNarrowed: minPeakElevation > 0,
                accessibility: "Minimum pass elevation filter"
            )
        case .sectors:
            sectorSummary()
        }
    }

    private func sectorSummary() -> ExpanderSummary {
        let mask = SatelliteModeFilter.horizonMask(from: sectorsRaw)
        let raised = SkySector.allCases.compactMap { sector -> String? in
            guard let minimum = mask[sector], minimum > 0 else {
                return nil
            }
            return minimum == SatelliteModeFilter.blockedElevation
                ? "\(sector.rawValue)✕"
                : "\(sector.rawValue)\(minimum)"
        }
        return ExpanderSummary(
            text: raised.isEmpty ? "Horizon" : "Horizon \(raised.joined(separator: ","))",
            isNarrowed: !raised.isEmpty,
            accessibility: "Horizon mask filter"
        )
    }

    private func bandSummary(
        arrow: String, raw: String, accessibility: String
    ) -> ExpanderSummary {
        let bands = SatelliteModeFilter.bandSelection(from: raw)
        let narrowed = bands.count < SatBand.allCases.count
        let letters = SatBand.allCases.filter(bands.contains).map(\.rawValue)
        return ExpanderSummary(
            text: "\(arrow) \(narrowed ? letters.joined(separator: ",") : "All")",
            isNarrowed: narrowed,
            accessibility: accessibility
        )
    }
}

// MARK: - SatelliteFilterSheet

/// The map's filter surface: every dimension laid out as always-visible
/// toggle rows (a Menu dismisses per tap — useless for multi-select), so
/// several changes are one gesture stream. Presented compact from the
/// map's ⋯ menu; no map real estate spent.
struct SatelliteFilterSheet: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            ScrollView {
                filterSections
            }
            .navigationTitle("Filter Satellites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @AppStorage(SatelliteModeFilter.uplinkBandKey) private var uplinkRaw = ""
    @AppStorage(SatelliteModeFilter.downlinkBandKey) private var downlinkRaw = ""

    private var filterSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Mode") {
                SatelliteBucketChipRow()
            }
            section("Uplink band ↑") {
                SatelliteBandChipRow(raw: $uplinkRaw)
            }
            section("Downlink band ↓") {
                SatelliteBandChipRow(raw: $downlinkRaw)
            }
            section("Next pass peaks ≥") {
                SatelliteElevationChipRow()
            }
            section("Horizon — min elevation by direction (tap to cycle)") {
                SatelliteHorizonChipRow()
            }
            section("Only") {
                SatelliteFilterToggleChips()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                content()
            }
        }
    }
}
