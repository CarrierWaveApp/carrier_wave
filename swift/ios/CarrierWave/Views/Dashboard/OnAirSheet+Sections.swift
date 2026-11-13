import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Filtered Spot Helpers

extension OnAirSheet {
    var spotBands: Set<String> {
        OnAirSpotFilter.decodeSet(from: bandFilterRaw)
    }

    var spotModes: Set<String> {
        OnAirSpotFilter.decodeSet(from: modeFilterRaw)
    }

    var filteredPOTASpots: [POTASpot] {
        OnAirSpotFilter.filterPOTA(
            potaSpots, bands: spotBands, modes: spotModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }

    var filteredSOTASpots: [SOTASpot] {
        OnAirSpotFilter.filterSOTA(
            sotaSpots, bands: spotBands, modes: spotModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }

    var filteredFriendSpots: [(callsign: String, spot: POTASpot)] {
        OnAirSpotFilter.filterFriends(
            friendSpots, bands: spotBands, modes: spotModes,
            maxAgeMinutes: spotMaxAgeMinutes
        )
    }
}

// MARK: - Contests, Friends, Band Conditions, POTA/SOTA Sections

extension OnAirSheet {
    // MARK: - Contests Section

    var contestsSection: some View {
        ContestsSectionView(contestService: contestService)
    }

    // MARK: - Friends on Air Section

    var friendsOnAirSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let count = filteredFriendSpots.count
            sectionHeader(
                "Friends on Air",
                icon: "person.2.fill",
                color: .green,
                badge: count > 0 ? "\(count) on air" : nil
            )

            if filteredFriendSpots.isEmpty {
                noDataCard("No friends on air right now")
            } else {
                friendSpotsList
            }
        }
    }

    var friendSpotsList: some View {
        VStack(spacing: 0) {
            ForEach(filteredFriendSpots, id: \.callsign) { item in
                sheetFriendRow(callsign: item.callsign, spot: item.spot)
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Band Conditions Section

    @ViewBuilder
    var bandConditionsSection: some View {
        if !bandEstimates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    "Band Conditions",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .blue
                )

                bandConditionsCard
            }
        }
    }

    var bandConditionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = solarData?.propagationRating {
                Text(summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ratingColor(summary))
                    .badgePill(ratingColor(summary).opacity(0.12))
            }

            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 8), count: 2
            )
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(bandEstimates) { band in
                    BandQualityGaugeRow(
                        bandName: band.band,
                        qualityIndex: band.quality.rawValue,
                        isSelected: false,
                        onTap: {}
                    )
                }
            }

            NavigationLink {
                ConditionsHistoryView(tourState: tourState)
            } label: {
                HStack {
                    Spacer()
                    Text("See Full History")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.blue)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - POTA Spots Section

    var potaSpotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let filtered = filteredPOTASpots
            let count = filtered.count
            sectionHeader(
                "POTA Spots",
                icon: "leaf.fill",
                color: .green,
                badge: count > 0 ? "\(count) active" : nil
            )

            if filtered.isEmpty {
                noDataCard("No POTA activators spotted")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.spotId) { spot in
                        sheetPOTARow(spot)
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - SOTA Spots Section

    var sotaSpotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let filtered = filteredSOTASpots
            let count = filtered.count
            sectionHeader(
                "SOTA Spots",
                icon: "mountain.2.fill",
                color: .orange,
                badge: count > 0 ? "\(count) active" : nil
            )

            if filtered.isEmpty {
                noDataCard("No SOTA activators spotted")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { spot in
                        sheetSOTARow(spot)
                    }
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Row Helpers

    func sheetFriendRow(callsign: String, spot: POTASpot) -> some View {
        Button {
            postSheetSpotNotification(
                callsign: spot.activator,
                frequencyMHz: spot.frequencyKHz.map { $0 / 1_000.0 },
                mode: spot.mode,
                ref: spot.reference,
                comment: spot.parkName
            )
        } label: {
            sheetFriendRowLabel(callsign: callsign, spot: spot)
        }
        .buttonStyle(.plain)
    }

    private func sheetFriendRowLabel(callsign: String, spot: POTASpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                HStack(spacing: 4) {
                    Text(callsign)
                        .font(.subheadline.weight(.semibold).monospaced())
                    if let name = operatorNames[callsign.uppercased()] {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    sheetClubBadges(for: callsign)
                    sheetContactBadge(for: callsign)
                }
                Spacer()
                if let band = BandUtilities.deriveBand(from: spot.frequencyKHz) {
                    Text(band)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(spot.mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(potaParkDisplay(spot))
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Spacer()
                Text(spot.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func sheetPOTARow(_ spot: POTASpot) -> some View {
        Button {
            postSheetSpotNotification(
                callsign: spot.activator,
                frequencyMHz: spot.frequencyKHz.map { $0 / 1_000.0 },
                mode: spot.mode,
                ref: spot.reference,
                comment: spot.parkName
            )
        } label: {
            sheetPOTARowLabel(spot)
        }
        .buttonStyle(.plain)
    }

    private func sheetPOTARowLabel(_ spot: POTASpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                HStack(spacing: 4) {
                    Text(spot.activator)
                        .font(.subheadline.weight(.semibold).monospaced())
                    if let name = operatorNames[spot.activator.uppercased()] {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    sheetClubBadges(for: spot.activator)
                    sheetContactBadge(for: spot.activator)
                }
                Spacer()
                if let band = BandUtilities.deriveBand(from: spot.frequencyKHz) {
                    Text(band)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(spot.mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(potaParkDisplay(spot))
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Spacer()
                Text(spot.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func sheetSOTARow(_ spot: SOTASpot) -> some View {
        Button {
            postSheetSpotNotification(
                callsign: spot.activatorCallsign,
                frequencyMHz: spot.frequencyMHz,
                mode: spot.mode,
                ref: spot.fullSummitReference,
                comment: spot.summitName
            )
        } label: {
            sheetSOTARowLabel(spot)
        }
        .buttonStyle(.plain)
    }

    private func sheetSOTARowLabel(_ spot: SOTASpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                HStack(spacing: 4) {
                    Text(spot.activatorCallsign)
                        .font(.subheadline.weight(.semibold).monospaced())
                    if let name = operatorNames[spot.activatorCallsign.uppercased()] {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    sheetClubBadges(for: spot.activatorCallsign)
                    sheetContactBadge(for: spot.activatorCallsign)
                }
                Spacer()
                if let khz = spot.frequencyKHz,
                   let band = BandUtilities.deriveBand(from: khz)
                {
                    Text(band)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(spot.mode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(spot.fullSummitReference) — \(spot.summitName)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Spacer()
                Text(spot.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Spot Navigation

    func postSheetSpotNotification(
        callsign: String,
        frequencyMHz: Double?,
        mode: String,
        ref: String?,
        comment: String?
    ) {
        var userInfo: [String: Any] = ["callsign": callsign, "mode": mode]
        if let freq = frequencyMHz {
            userInfo["frequencyMHz"] = freq
        }
        if let ref {
            userInfo["ref"] = ref
        }
        if let comment {
            userInfo["comment"] = comment
        }
        dismiss()
        NotificationCenter.default.post(
            name: .didSelectHunterSpot,
            object: nil,
            userInfo: userInfo
        )
    }

    // MARK: - Shared Helpers

    private func potaParkDisplay(_ spot: POTASpot) -> String {
        var parts = [spot.reference]
        if let name = spot.parkName, !name.isEmpty {
            parts.append(name)
        } else if let loc = spot.locationDesc, !loc.isEmpty {
            parts.append(loc)
        }
        return parts.joined(separator: " — ")
    }

    @ViewBuilder
    func sheetClubBadges(for callsign: String) -> some View {
        let clubs = ClubsSyncService.shared.clubs(for: callsign)
        if !clubs.isEmpty {
            HStack(spacing: 2) {
                Image(systemName: "person.3.fill")
                    .font(.caption2)
                Text(clubs.joined(separator: ", "))
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.blue.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    @ViewBuilder
    func sheetContactBadge(for callsign: String) -> some View {
        let count = contactCounts[callsign.uppercased()] ?? 0
        if count > 1 {
            ContactCountBadge(count: count)
        }
    }
}
