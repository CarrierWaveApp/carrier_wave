import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SpotGroup

/// A run of consecutive spots of the same type (human or RBN) when sorted by time.
/// Human spots are individual rows; consecutive RBN spots collapse into an accordion.
enum SpotGroup: Identifiable {
    case human(SessionSpot)
    case rbnRun(id: UUID, spots: [SessionSpot])

    // MARK: Internal

    var id: UUID {
        switch self {
        case let .human(spot): spot.id
        case let .rbnRun(id, _): id
        }
    }
}

// MARK: - SessionSpotsSection

/// Section displaying persisted spots for a completed logging session.
/// Collapsible by default. Human spots shown individually; consecutive RBN
/// spots grouped into mini-accordions interspersed chronologically.
struct SessionSpotsSection: View {
    // MARK: Internal

    let session: LoggingSession
    var spotQSOMatch: SpotQSOMatch?

    var body: some View {
        if !spots.isEmpty {
            Section {
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

                    ForEach(buildSpotGroups(from: nonClubSpots)) { group in
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
            }
            .task { await loadSpots() }
        } else {
            Color.clear
                .frame(height: 0)
                .listRowSeparator(.hidden)
                .task { await loadSpots() }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var spots: [SessionSpot] = []
    @State private var isSectionExpanded = false

    private var sectionTitle: String {
        let count = spots.count
        return "\(count) Spot\(count == 1 ? "" : "s")"
    }

    private var clubSpots: [SessionSpot] {
        spots.filter {
            !ClubsSyncService.shared.clubs(for: $0.callsign).isEmpty
        }
    }

    private var nonClubSpots: [SessionSpot] {
        spots.filter {
            ClubsSyncService.shared.clubs(for: $0.callsign).isEmpty
        }
    }

    /// Group spots into runs: each human spot is standalone,
    /// consecutive RBN spots are collapsed into a single accordion.
    private func buildSpotGroups(from spotList: [SessionSpot]) -> [SpotGroup] {
        let sorted = spotList.sorted { $0.timestamp > $1.timestamp }
        var groups: [SpotGroup] = []
        var currentRBNRun: [SessionSpot] = []

        for spot in sorted {
            if spot.isRBN {
                currentRBNRun.append(spot)
            } else {
                if !currentRBNRun.isEmpty {
                    groups.append(.rbnRun(
                        id: currentRBNRun[0].id,
                        spots: currentRBNRun
                    ))
                    currentRBNRun = []
                }
                groups.append(.human(spot))
            }
        }
        if !currentRBNRun.isEmpty {
            groups.append(.rbnRun(
                id: currentRBNRun[0].id,
                spots: currentRBNRun
            ))
        }
        return groups
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

// MARK: - RBNRunRow

/// Collapsible row for a run of consecutive RBN spots.
struct RBNRunRow: View {
    // MARK: Internal

    let spots: [SessionSpot]

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .foregroundStyle(.blue)

                Text("\(spots.count) RBN")
                    .font(.subheadline)

                regionPills

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)

        if isExpanded {
            ForEach(spots) { spot in
                SessionSpotRow(spot: spot, isPOTAHighlight: false)
            }
        }
    }

    // MARK: Private

    @State private var isExpanded = false

    private var regionPills: some View {
        let grouped = Dictionary(grouping: spots, by: \.spotRegion)
        let sorted = grouped.sorted { $0.value.count > $1.value.count }
        return HStack(spacing: 4) {
            ForEach(sorted.prefix(3), id: \.key) { region, regionSpots in
                Text("\(region.shortName) \(regionSpots.count)")
                    .font(.caption2)
                    .lineLimit(1)
                    .fixedSize()
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
}

// MARK: - SessionSpotRow

/// Individual spot row for the session detail view.
struct SessionSpotRow: View {
    // MARK: Internal

    let spot: SessionSpot
    let isPOTAHighlight: Bool
    var isLogged: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            mainRow
            if let comments = spot.comments, !comments.isEmpty {
                Text(comments)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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
        let freq = spot.frequencyKHz
        if freq == freq.rounded(.down) {
            return String(format: "%.0f", freq)
        }
        return String(format: "%.1f", freq)
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            if spot.isSelfSpot {
                Image(systemName: "megaphone.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isPOTAHighlight {
                Image(systemName: "leaf.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                regionBadge
            }

            Text(displayCallsign)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .layoutPriority(1)

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

            Spacer()

            Text(formattedFrequency)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(spot.mode)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let snr = spot.snr {
                Text("\(snr) dB")
                    .font(.caption2)
                    .foregroundStyle(snrColor(snr))
                    .lineLimit(1)
            }

            if let wpm = spot.wpm {
                Text("\(wpm) wpm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(spot.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !spot.isSelfSpot, let isLogged {
                Image(
                    systemName: isLogged
                        ? "checkmark.circle.fill" : "circle.dashed"
                )
                .font(.caption)
                .foregroundStyle(isLogged ? .green : .secondary)
            }
        }
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
            .fixedSize()
            .lineLimit(1)
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
