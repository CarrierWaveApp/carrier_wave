import CarrierWaveData
import SwiftUI

// MARK: - Club Spot Sections

extension POTASpotsView {
    var clubPOTASpots: [POTASpot] {
        filteredSpots.filter {
            !ClubsSyncService.shared.clubs(for: $0.activator).isEmpty
        }
    }

    var clubSOTASpots: [SOTASpot] {
        filteredSOTASpots.filter {
            !ClubsSyncService.shared.clubs(for: $0.activatorCallsign).isEmpty
        }
    }

    var hasClubSpots: Bool {
        !clubPOTASpots.isEmpty || !clubSOTASpots.isEmpty
    }

    var nonClubPOTASpots: [POTASpot] {
        guard hasClubSpots else {
            return filteredSpots
        }
        let clubCallsigns = Set(
            clubPOTASpots.map { $0.activator.uppercased() }
        )
        return filteredSpots.filter {
            !clubCallsigns.contains($0.activator.uppercased())
        }
    }

    var nonClubSOTASpots: [SOTASpot] {
        guard hasClubSpots else {
            return filteredSOTASpots
        }
        let clubCallsigns = Set(
            clubSOTASpots.map { $0.activatorCallsign.uppercased() }
        )
        return filteredSOTASpots.filter {
            !clubCallsigns.contains($0.activatorCallsign.uppercased())
        }
    }

    var nonClubSpotsByBand: [(band: String, spots: [POTASpot])] {
        Self.groupSpotsByBand(nonClubPOTASpots)
    }

    var nonClubSOTAByBand: [(band: String, spots: [SOTASpot])] {
        Self.groupSOTASpotsByBand(nonClubSOTASpots)
    }

    // MARK: - Section Views

    var nonClubPotaSpotsSection: some View {
        ForEach(nonClubSpotsByBand, id: \.band) { section in
            Section {
                ForEach(section.spots) { spot in
                    let result = workedResults[spot.activator.uppercased()]
                        ?? .notWorked
                    POTASpotRow(
                        spot: spot,
                        userCallsign: userCallsign,
                        friendCallsigns: friendCallsigns,
                        workedResult: result
                    ) {
                        onSelectSpot?(spot)
                    }
                    .opacity(spot.isAutomatedSpot ? 0.7 : 1.0)
                    .contextMenu { tuneInContextMenu(for: spot) }
                    Divider()
                        .padding(.leading, 92)
                }
            } header: {
                POTASpotsBandHeader(band: section.band)
            }
        }
    }

    @ViewBuilder
    var nonClubSotaSpotsSection: some View {
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
                        ) {
                            // SOTA spot tapped — not yet wired to QSO prefill
                        }
                        Divider()
                            .padding(.leading, 92)
                    }
                } header: {
                    SOTASpotsBandHeader(band: section.band)
                }
            }
        }
    }

    var clubSpotsSection: some View {
        Section {
            ForEach(clubPOTASpots) { spot in
                let result = workedResults[spot.activator.uppercased()]
                    ?? .notWorked
                POTASpotRow(
                    spot: spot,
                    userCallsign: userCallsign,
                    friendCallsigns: friendCallsigns,
                    workedResult: result
                ) {
                    onSelectSpot?(spot)
                }
                .contextMenu { tuneInContextMenu(for: spot) }
                Divider()
                    .padding(.leading, 92)
            }
            ForEach(clubSOTASpots) { spot in
                let callKey = spot.activatorCallsign.uppercased()
                let result = workedResults[callKey] ?? .notWorked
                SOTASpotRow(
                    spot: spot,
                    friendCallsigns: friendCallsigns,
                    workedResult: result
                ) {}
                Divider()
                    .padding(.leading, 92)
            }
        } header: {
            ClubSpotsSectionHeader()
        }
    }

    func tuneInContextMenu(for spot: POTASpot) -> some View {
        Button {
            let tuneInSpot = TuneInSpot(from: spot)
            TuneInManager.shared.requestTuneIn(to: tuneInSpot)
        } label: {
            Label(
                "Tune In to \(spot.activator)",
                systemImage: "radio"
            )
        }
    }
}
