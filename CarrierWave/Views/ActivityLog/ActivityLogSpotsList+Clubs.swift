import CarrierWaveData
import SwiftUI

// MARK: - Club Spot Grouping

extension ActivityLogSpotsList {
    var clubFilteredSpots: [EnrichedSpot] {
        if filters.clubOnly {
            return sortedSpots.filter {
                !ClubsSyncService.shared.clubs(for: $0.spot.callsign).isEmpty
            }
        }
        return sortedSpots
    }

    var clubMemberSpots: [EnrichedSpot] {
        guard !filters.clubOnly else {
            return []
        }
        return clubFilteredSpots.filter {
            !ClubsSyncService.shared.clubs(for: $0.spot.callsign).isEmpty
        }
    }

    var otherSpots: [EnrichedSpot] {
        guard !filters.clubOnly else {
            return clubFilteredSpots
        }
        return clubFilteredSpots.filter {
            ClubsSyncService.shared.clubs(for: $0.spot.callsign).isEmpty
        }
    }

    func clubSectionHeader(_ title: String) -> some View {
        HStack {
            if title == "Club Members" {
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }
}
