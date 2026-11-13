import Foundation

// MARK: - SpotListOrdering

/// Pure ordering helpers for the spots list. Kept free of SwiftUI so the
/// row-ordering rules are unit-testable.
enum SpotListOrdering {
    /// The list's default sort: newest spot first.
    static let defaultSortOrder = [KeyPathComparator(\EnrichedSpot.sortTimestamp, order: .reverse)]

    /// Whether `sortOrder` is still the default time sort (as opposed to a
    /// column the user clicked). Self-spot pinning only applies here — once
    /// the operator sorts by callsign / frequency / distance the list must
    /// honour that order exactly.
    static func isDefaultSort(_ sortOrder: [KeyPathComparator<EnrichedSpot>]) -> Bool {
        sortOrder == defaultSortOrder
    }

    /// Whether `spot` belongs to the operator. Empty callsigns never match,
    /// so a fresh install with no callsign configured pins nothing.
    static func isSelfSpot(_ spot: EnrichedSpot, userCallsign: String) -> Bool {
        let trimmed = userCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        return spot.spot.isSelfSpot(userCallsign: trimmed)
    }

    /// Move the operator's own spots to the top of an already-sorted list,
    /// preserving relative order within each group (stable partition).
    /// Returns `spots` untouched when the user has chosen a non-default sort
    /// or has no callsign configured.
    static func pinningSelfSpots(
        _ spots: [EnrichedSpot],
        userCallsign: String,
        sortOrder: [KeyPathComparator<EnrichedSpot>]
    ) -> [EnrichedSpot] {
        guard isDefaultSort(sortOrder),
              !userCallsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return spots
        }
        var own: [EnrichedSpot] = []
        var others: [EnrichedSpot] = []
        own.reserveCapacity(4)
        others.reserveCapacity(spots.count)
        for spot in spots {
            if isSelfSpot(spot, userCallsign: userCallsign) {
                own.append(spot)
            } else {
                others.append(spot)
            }
        }
        guard !own.isEmpty else {
            return spots
        }
        return own + others
    }
}
