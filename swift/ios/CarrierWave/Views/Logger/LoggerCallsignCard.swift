import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import SwiftUI

// MARK: - LoggerCallsignCard

/// Displays callsign lookup information in the logger
struct LoggerCallsignCard: View {
    // MARK: Internal

    let info: CallsignInfo
    var previousQSOCount: Int = 0
    var myGrid: String?
    var potaSpots: [POTASpot] = []
    /// SOTA spot the contacted station is currently activating, if any.
    /// Populated by `LoggerView` from the shared `SOTASpotsCache` so the
    /// card can show an S2S badge alongside the existing P2P row when
    /// the typed callsign matches a current SOTAwatch spot.
    var sotaSpot: SOTASpot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: callsign, emoji, name, flag
            HStack(spacing: 6) {
                Text(info.callsign)
                    .font(.headline.weight(.bold).monospaced())

                notesDisplay

                if let name = info.displayName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let flag = CallsignFlagHelper.countryFlag(for: info.callsign) {
                    Text(flag)
                        .font(.title3)
                }
            }

            // Row 1.5: NATO phonetic spelling (opt-in)
            if showPhonetics {
                Text(NATOPhonetics.spell(info.callsign))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Row 2: all detail chips in one wrapping group
            if hasDetails {
                detailChips
            }

            // Row 2.5: P2P park-to-park enrichment (horizontal scroll)
            if !potaSpots.isEmpty {
                p2pParkRow
            }

            // Row 2.6: S2S summit-to-summit enrichment
            if let sotaSpot {
                s2sSummitRow(sotaSpot)
            }

            // Row 3: note, previous callsign, change note, source — compact
            footerRow
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @AppStorage("callsignNotesDisplayMode") private var notesDisplayMode = "emoji"
    @AppStorage("loggerShowPhonetics") private var showPhonetics = false

    private var hasDetails: Bool {
        info.qth != nil || info.grid != nil || info.state != nil || info.country != nil
            || previousQSOCount > 0 || distanceKm != nil
            || !(info.memberships ?? []).isEmpty
    }

    /// Distance in km from user's grid to station's grid
    private var distanceKm: Double? {
        guard let myGrid, !myGrid.isEmpty,
              let theirGrid = info.grid, !theirGrid.isEmpty,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }
        let myLoc = CLLocation(latitude: myCoord.latitude, longitude: myCoord.longitude)
        let theirLoc = CLLocation(latitude: theirCoord.latitude, longitude: theirCoord.longitude)
        return myLoc.distance(from: theirLoc) / 1_000.0
    }

    /// Bearing in degrees from user's grid to station's grid
    private var bearingDegrees: Double? {
        guard let myGrid, !myGrid.isEmpty,
              let theirGrid = info.grid, !theirGrid.isEmpty,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }
        return Self.bearing(from: myCoord, to: theirCoord)
    }

    private var sourceLabel: String {
        switch info.source {
        case .poloNotes:
            "from Polo Notes"
        case .qrz:
            "from QRZ"
        case .hamdb:
            "from HamDB"
        case .fcc:
            "from FCC"
        }
    }

    /// Deduplicated spots by park reference, preserving order
    private var uniqueParkRefs: [POTASpot] {
        var seen: Set<String> = []
        return potaSpots.filter { seen.insert($0.reference).inserted }
    }

    @ViewBuilder
    private var notesDisplay: some View {
        if notesDisplayMode == "sources" {
            // Show source names as chips
            if let sources = info.matchingSources, !sources.isEmpty {
                HStack(spacing: 4) {
                    ForEach(sources, id: \.self) { source in
                        Text(source)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
        } else {
            // Show combined emoji
            if let emoji = info.combinedEmoji {
                Text(emoji)
                    .font(.title2)
            }
        }
    }

    private var detailChips: some View {
        ChipFlowLayout(spacing: 6) {
            if let qth = info.qth {
                DetailChip(text: qth)
            }

            if let state = info.state {
                DetailChip(text: state)
            }

            if let grid = info.grid {
                DetailChip(text: grid)
            }

            if let country = info.country {
                DetailChip(text: country)
            }

            if let km = distanceKm {
                DetailChip(
                    text: UnitFormatter.distance(km),
                    icon: "arrow.triangle.swap"
                )
            }

            if let deg = bearingDegrees {
                DetailChip(
                    text: "\(Int(deg.rounded()))\u{00B0}",
                    icon: "location.north.fill",
                    iconRotation: deg
                )
            }

            if previousQSOCount > 0 {
                ContactCountBadge(count: previousQSOCount, showLabel: true)
            }

            ForEach(info.memberships ?? [], id: \.sourceSlug) { membership in
                MembershipChip(membership: membership)
            }
        }
    }

    private var p2pParkRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Leading P2P badge
                Label("P2P", systemImage: "tree.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green, in: Capsule())

                // One chip per park
                ForEach(uniqueParkRefs, id: \.reference) { spot in
                    HStack(spacing: 4) {
                        Text(spot.reference)
                            .font(.caption.weight(.medium).monospaced())
                        if let name = spot.parkName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var footerRow: some View {
        let hasFooterContent = info.note != nil
            || info.previousCallsign != nil
            || info.callsignChangeNote != nil

        if hasFooterContent {
            HStack(spacing: 8) {
                if let note = info.note, !note.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                        Text(CallsignInfo.parseNoteMarkdown(note))
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let previousCall = info.previousCallsign {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.arrow.left")
                        Text("Previously \(previousCall)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let changeNote = info.callsignChangeNote {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(changeNote)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                Spacer()

                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            HStack {
                Spacer()
                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Mirrors `p2pParkRow` for SOTA. Each spot only covers one summit at a
    /// time so this is a single-summit pill, not a horizontal list.
    private func s2sSummitRow(_ spot: SOTASpot) -> some View {
        HStack(spacing: 6) {
            Label("S2S", systemImage: "mountain.2.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange, in: Capsule())

            HStack(spacing: 4) {
                Text(spot.fullSummitReference)
                    .font(.caption.weight(.medium).monospaced())
                Text(spot.summitName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15))
            .clipShape(Capsule())

            Spacer(minLength: 0)
        }
    }

    /// Great-circle initial bearing between two coordinates
    private static func bearing(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LoggerCallsignCard(
            info: CallsignInfo(
                callsign: "W1AW",
                name: "ARRL Headquarters Station",
                note: "Official ARRL station - always great to work!",
                emoji: "🏛️",
                qth: "Newington",
                state: "CT",
                country: "United States",
                grid: "FN31pr",
                source: .poloNotes
            ),
            myGrid: "CN87"
        )

        LoggerCallsignCard(
            info: CallsignInfo(
                callsign: "DL1ABC",
                name: "Hans Mueller",
                note: nil,
                emoji: nil,
                qth: "Berlin",
                country: "Germany",
                grid: "JO31",
                source: .qrz
            ),
            myGrid: "CN87",
            potaSpots: [
                POTASpot(
                    spotId: 1, activator: "DL1ABC", frequency: "14062",
                    mode: "CW", reference: "DL-0001",
                    parkName: "Bavarian Forest", spotTime: "2026-03-23T12:00:00",
                    spotter: "DL2XYZ", comments: nil, source: nil,
                    name: nil, locationDesc: "DL-BY"
                ),
                POTASpot(
                    spotId: 2, activator: "DL1ABC", frequency: "14062",
                    mode: "CW", reference: "DL-0042",
                    parkName: "Black Forest", spotTime: "2026-03-23T12:00:00",
                    spotter: "DL2XYZ", comments: nil, source: nil,
                    name: nil, locationDesc: "DL-BW"
                ),
            ]
        )

        CallsignLookupErrorBanner(error: .noQRZApiKey)
        CallsignLookupErrorBanner(error: .qrzAuthFailed)
        CallsignLookupErrorBanner(error: .networkError("Connection timed out"))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
