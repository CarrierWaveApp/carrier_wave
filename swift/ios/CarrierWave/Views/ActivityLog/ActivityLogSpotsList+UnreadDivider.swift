import CarrierWaveData
import SwiftUI

// MARK: - Spot Ordering + Unread Divider

/// Spot list ordering (`sortedSpots`) and the unread divider helpers, split
/// out of the main type so `ActivityLogSpotsList` stays under the project's
/// 300-line struct-body limit. State (`sortOrder`, `workedResults`,
/// `sessionDividerBoundary`, `lastViewedSpotTimestamp`) is declared on the
/// main type body so SwiftUI sees a single owner; this file only contains
/// pure functions of that state.
extension ActivityLogSpotsList {
    /// Primary sort (by sortOrder) followed by a non-dupes-first / dupes-last
    /// partition. The dupe partition keeps already-worked stations from
    /// clogging the top of the list.
    var sortedSpots: [EnrichedSpot] {
        let primarySorted: [EnrichedSpot] = switch sortOrder {
        case .recent:
            dedupedSpots.sorted {
                ($0.spot.timestamp, $0.spot.callsign)
                    > ($1.spot.timestamp, $1.spot.callsign)
            }
        case .frequency:
            dedupedSpots.sorted {
                ($0.spot.frequencyKHz, $0.spot.callsign)
                    < ($1.spot.frequencyKHz, $1.spot.callsign)
            }
        case .needs:
            dedupedSpots.sorted {
                let lp = $0.highestNeedPriority?.rawValue ?? -1
                let rp = $1.highestNeedPriority?.rawValue ?? -1
                if lp != rp {
                    return lp > rp
                }
                return $0.spot.timestamp > $1.spot.timestamp
            }
        }

        let nonDupes = primarySorted.filter { spot in
            let key = spot.spot.callsign.uppercased()
            let result = workedResults[key] ?? .notWorked
            return !result.isDupe(
                on: spot.spot.band,
                mode: spot.spot.mode,
                park: spot.spot.parkRef
            )
        }
        let dupes = primarySorted.filter { spot in
            let key = spot.spot.callsign.uppercased()
            let result = workedResults[key] ?? .notWorked
            return result.isDupe(
                on: spot.spot.band,
                mode: spot.spot.mode,
                park: spot.spot.parkRef
            )
        }
        return nonDupes + dupes
    }

    /// Returns the index of the first spot that is *not* newer than the frozen
    /// session boundary — i.e. the row above which to insert the divider. Nil
    /// when the divider should be hidden (wrong sort, no prior view, no new
    /// spots, or every visible spot is new).
    func newSinceLastViewIndex(in rowSpots: [EnrichedSpot]) -> Int? {
        guard sortOrder == .recent,
              sessionDividerBoundary > 0,
              !rowSpots.isEmpty
        else {
            return nil
        }
        guard let firstOld = rowSpots.firstIndex(where: {
            $0.spot.timestamp.timeIntervalSince1970 <= sessionDividerBoundary
        }) else {
            // Every visible spot is newer than the boundary — a divider above
            // index 0 would read as "all of these are new", which is the same
            // information the row recency already conveys.
            return nil
        }
        // No new spots ahead of the boundary → nothing to mark.
        return firstOld > 0 ? firstOld : nil
    }

    func newSinceLastViewDivider(newCount: Int) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.blue.opacity(0.4))
                .frame(height: 1)
            Text("\(newCount) new since you looked")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
                .lineLimit(1)
                .fixedSize()
            Capsule()
                .fill(Color.blue.opacity(0.4))
                .frame(height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(newCount) new spots since last view")
    }
}
