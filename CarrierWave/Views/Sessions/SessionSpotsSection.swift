import SwiftData
import SwiftUI

// MARK: - SessionSpotsSection

/// Section displaying persisted spots for a completed logging session.
/// POTA/human spots shown individually at top, RBN spots collapsed by default.
struct SessionSpotsSection: View {
    // MARK: Internal

    let session: LoggingSession

    var body: some View {
        Group {
            if !spots.isEmpty {
                Section(sectionTitle) {
                    // POTA spots shown individually at top
                    ForEach(potaSpots) { spot in
                        SessionSpotRow(spot: spot, isPOTAHighlight: true)
                    }

                    // RBN spots collapsed by default
                    if !rbnSpots.isEmpty {
                        rbnSummaryRow
                        if isRBNExpanded {
                            ForEach(rbnSpots) { spot in
                                SessionSpotRow(spot: spot, isPOTAHighlight: false)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadSpots()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var spots: [SessionSpot] = []
    @State private var isRBNExpanded = false

    private var potaSpots: [SessionSpot] {
        spots.filter(\.isPOTA).sorted { $0.timestamp > $1.timestamp }
    }

    private var rbnSpots: [SessionSpot] {
        spots.filter(\.isRBN).sorted { $0.timestamp > $1.timestamp }
    }

    private var sectionTitle: String {
        let count = spots.count
        return "\(count) Spot\(count == 1 ? "" : "s")"
    }

    private var rbnSummaryRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isRBNExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .foregroundStyle(.blue)

                Text("\(rbnSpots.count) RBN spot\(rbnSpots.count == 1 ? "" : "s")")
                    .font(.subheadline)

                regionPills

                Spacer()

                Image(systemName: isRBNExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var regionPills: some View {
        let grouped = Dictionary(grouping: rbnSpots, by: \.spotRegion)
        let sorted = grouped.sorted { $0.value.count > $1.value.count }
        return HStack(spacing: 4) {
            ForEach(sorted.prefix(3), id: \.key) { region, regionSpots in
                Text("\(region.shortName) \(regionSpots.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if sorted.count > 3 {
                Text("+\(sorted.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Use .task for performance compliance (no @Query)
    private func loadSpots() async {
        let sessionId = session.id
        let predicate = #Predicate<SessionSpot> { spot in
            spot.loggingSessionId == sessionId
        }
        var descriptor = FetchDescriptor<SessionSpot>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        spots = (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - SessionSpotRow

/// Individual spot row for the session detail view.
struct SessionSpotRow: View {
    // MARK: Internal

    let spot: SessionSpot
    let isPOTAHighlight: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Source icon
            if isPOTAHighlight {
                Image(systemName: "leaf.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                regionBadge
            }

            // Callsign or spotter
            Text(displayCallsign)
                .font(.system(.subheadline, design: .monospaced))

            Spacer()

            // Frequency
            Text(formattedFrequency)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Mode
            Text(spot.mode)
                .font(.caption)
                .foregroundStyle(.secondary)

            // SNR / WPM for RBN
            if let snr = spot.snr {
                Text("\(snr) dB")
                    .font(.caption2)
                    .foregroundStyle(snrColor(snr))
            }

            if let wpm = spot.wpm {
                Text("\(wpm) wpm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Distance
            if let meters = spot.distanceMeters {
                Text(UnitFormatter.distance(meters / 1_000.0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Time
            Text(spot.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    private var displayCallsign: String {
        if isPOTAHighlight {
            if let spotter = spot.spotter {
                return spotter
            }
            return spot.callsign
        }
        return spot.spotter ?? spot.callsign
    }

    private var formattedFrequency: String {
        String(format: "%.1f", spot.frequencyKHz)
    }

    private var regionBadge: some View {
        Text(spot.spotRegion.shortName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(regionColor(spot.spotRegion))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func regionColor(_ region: SpotRegion) -> Color {
        switch region {
        case .neUS,
             .seUS,
             .mwUS,
             .swUS,
             .nwUS: .blue
        case .canada: .red
        case .mexico,
             .caribbean,
             .southAmerica: .orange
        case .europe: .purple
        case .asia: .pink
        case .oceania: .teal
        case .africa: .brown
        case .other: .gray
        }
    }

    private func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 25...: .green
        case 15...: .blue
        case 5...: .orange
        default: .red
        }
    }
}
