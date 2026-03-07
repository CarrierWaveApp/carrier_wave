import CarrierWaveData
import Foundation

// MARK: - ActivityGroup

/// Groups consecutive same-callsign, same-type ActivityItems within a time window.
struct ActivityGroup: Identifiable {
    let id: UUID
    let callsign: String
    let activityType: ActivityType
    let items: [ActivityItem]

    var primaryItem: ActivityItem {
        items[0]
    }

    var latestTimestamp: Date {
        primaryItem.timestamp
    }

    var count: Int {
        items.count
    }

    var isConsolidated: Bool {
        count > 1
    }
}

// MARK: - Grouping Logic

enum ActivityGrouping {
    /// Types that should be consolidated when multiple appear from the same callsign.
    private static let consolidatableTypes: Set<ActivityType> = [
        .dxContact,
        .workedFriend,
        .newDXCCEntity,
        .newBand,
        .newMode,
    ]

    /// Maximum time gap between items to be grouped together (2 hours).
    private static let groupingWindowSeconds: TimeInterval = 2 * 3_600

    /// Groups activity items by (callsign, activityType) within a time window.
    /// Items are expected to be sorted by timestamp descending (newest first).
    static func group(_ items: [ActivityItem]) -> [ActivityGroup] {
        var groups: [ActivityGroup] = []
        var index = 0

        while index < items.count {
            let current = items[index]

            guard consolidatableTypes.contains(current.activityType) else {
                // Non-consolidatable: always a single-item group
                groups.append(ActivityGroup(
                    id: current.id,
                    callsign: current.callsign,
                    activityType: current.activityType,
                    items: [current]
                ))
                index += 1
                continue
            }

            // Collect consecutive items with same callsign + type within window
            var grouped = [current]
            var nextIndex = index + 1

            while nextIndex < items.count {
                let candidate = items[nextIndex]
                guard candidate.callsign == current.callsign,
                      candidate.activityType == current.activityType,
                      isWithinWindow(grouped.last!, candidate)
                else {
                    break
                }
                grouped.append(candidate)
                nextIndex += 1
            }

            groups.append(ActivityGroup(
                id: current.id,
                callsign: current.callsign,
                activityType: current.activityType,
                items: grouped
            ))
            index = nextIndex
        }

        return groups
    }

    private static func isWithinWindow(
        _ newer: ActivityItem,
        _ older: ActivityItem
    ) -> Bool {
        abs(newer.timestamp.timeIntervalSince(older.timestamp)) <= groupingWindowSeconds
    }
}

// MARK: - ActivityGroup Summary Helpers

extension ActivityGroup {
    /// Summary text for consolidated DX contact groups.
    var dxContactSummary: String {
        let maxDistance = items.compactMap { $0.details?.distanceKm }.max() ?? 0
        let distanceStr = UnitFormatter.distance(maxDistance)
        return "Worked \(count) DX stations (up to \(distanceStr))"
    }

    /// Summary text for consolidated worked-friend groups.
    var workedFriendSummary: String {
        let callsigns = items.compactMap { $0.details?.workedCallsign }
        if callsigns.count <= 2 {
            return "Worked \(callsigns.joined(separator: " & "))"
        }
        return "Worked \(count) friends"
    }

    /// Summary text for consolidated milestone groups (new DXCC/band/mode).
    var milestoneSummary: String {
        switch activityType {
        case .newDXCCEntity:
            let entities = items.compactMap { $0.details?.entityName }
            if entities.count <= 2 {
                return "Worked \(entities.joined(separator: " & ")) for the first time"
            }
            return "Worked \(count) new DXCC entities"
        case .newBand:
            let bands = items.compactMap { $0.details?.band }
            return "First contacts on \(bands.joined(separator: ", "))"
        case .newMode:
            let modes = items.compactMap { $0.details?.mode }
            return "First contacts on \(modes.joined(separator: ", "))"
        default:
            return "\(count) activities"
        }
    }

    /// Unique bands across all items in the group.
    var uniqueBands: [String] {
        let bands = items.compactMap { $0.details?.band }
        return Array(Set(bands)).sorted()
    }
}
