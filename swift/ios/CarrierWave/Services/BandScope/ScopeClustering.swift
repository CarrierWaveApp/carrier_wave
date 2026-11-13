import UIKit

// MARK: - ScopeCluster

/// One Scope list row: a chained group of spots within
/// `clusterWidthKHz` of the running cluster edge (spec §10). Single-spot
/// clusters are the common case.
struct ScopeCluster: Identifiable {
    let spots: [EnrichedSpot]

    var id: String {
        spots[0].id
    }

    var lead: EnrichedSpot {
        spots[0]
    }

    var minFrequencyKHz: Double {
        spots[0].spot.frequencyKHz
    }

    var maxFrequencyKHz: Double {
        spots[spots.count - 1].spot.frequencyKHz
    }

    var isPileup: Bool {
        spots.count > 1
    }
}

// MARK: - ScopeGap

/// Clear spectrum between two consecutive clusters (spec §4). Only gaps
/// ≥ `gapAffordanceKHz` become tappable QSY rows; smaller ones render as a
/// plain hairline. ALWAYS computed on unfiltered data (§17) — a gap claim
/// must never be falsified by a spot the current filter is hiding.
struct ScopeGap: Identifiable {
    let afterClusterID: String
    let gapKHz: Double
    let midpointKHz: Double

    var id: String {
        "gap-\(afterClusterID)"
    }

    var isQSYAffordance: Bool {
        gapKHz >= BandScopeTunables.gapAffordanceKHz
    }
}

// MARK: - ScopeClustering

/// Pure Scope-list assembly: frequency sort → chained pileup clustering →
/// gap dividers → busted-copy flags. No SwiftUI, fully unit-testable.
enum ScopeClustering {
    /// Cluster frequency-sorted spots by chaining: a spot joins the
    /// running cluster while it is within `widthKHz` of the cluster's
    /// current edge (§10 — chained, not bucketed).
    static func clusters(
        of spots: [EnrichedSpot],
        widthKHz: Double = BandScopeTunables.clusterWidthKHz
    ) -> [ScopeCluster] {
        let sorted = spots.sorted { $0.spot.frequencyKHz < $1.spot.frequencyKHz }
        var result: [ScopeCluster] = []
        var current: [EnrichedSpot] = []
        for spot in sorted {
            let chains = current.last.map {
                spot.spot.frequencyKHz - $0.spot.frequencyKHz <= widthKHz
            } ?? false
            if chains {
                current.append(spot)
            } else {
                if !current.isEmpty {
                    result.append(ScopeCluster(spots: current))
                }
                current = [spot]
            }
        }
        if !current.isEmpty {
            result.append(ScopeCluster(spots: current))
        }
        return result
    }

    /// Gaps between consecutive clusters: last spot of the previous to
    /// first of the next (§4).
    static func gaps(between clusters: [ScopeCluster]) -> [ScopeGap] {
        guard clusters.count > 1 else {
            return []
        }
        return zip(clusters, clusters.dropFirst()).map { previous, next in
            let gap = next.minFrequencyKHz - previous.maxFrequencyKHz
            return ScopeGap(
                afterClusterID: previous.id,
                gapKHz: gap,
                midpointKHz: previous.maxFrequencyKHz + gap / 2
            )
        }
    }

    /// Busted-copy suspects within a cluster (§10): an edit-distance-1
    /// callsign pair on (nearly) the same frequency where exactly one
    /// side is skimmer-sourced — the skimmer copy is the suspect
    /// (N5RAD/I5RAD). Human-vs-human pairs stay unflagged: no basis to
    /// pick a victim. Scope badges suspects; Heard drops them entirely.
    static func bustedSuspectIDs(in cluster: ScopeCluster) -> Set<String> {
        guard cluster.isPileup else {
            return []
        }
        var suspects: Set<String> = []
        let spots = cluster.spots
        for (index, lhs) in spots.enumerated() {
            for rhs in spots[(index + 1)...] {
                guard isEditDistanceOne(lhs.spot.callsign, rhs.spot.callsign) else {
                    continue
                }
                switch (lhs.spot.source.isAutomated, rhs.spot.source.isAutomated) {
                case (true, false): suspects.insert(lhs.id)
                case (false, true): suspects.insert(rhs.id)
                default: break
                }
            }
        }
        return suspects
    }

    /// All busted suspects across a clustered list — Heard uses this to
    /// dedupe fully (§10).
    static func bustedSuspectIDs(in clusters: [ScopeCluster]) -> Set<String> {
        clusters.reduce(into: Set<String>()) { result, cluster in
            result.formUnion(bustedSuspectIDs(in: cluster))
        }
    }

    /// True when the two callsigns differ by exactly one substitution,
    /// insertion, or deletion (case-insensitive).
    static func isEditDistanceOne(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.uppercased())
        let right = Array(rhs.uppercased())
        if left == right {
            return false
        }
        let lengthDelta = left.count - right.count
        switch lengthDelta {
        case 0:
            var mismatches = 0
            for (lchar, rchar) in zip(left, right) where lchar != rchar {
                mismatches += 1
                if mismatches > 1 {
                    return false
                }
            }
            return mismatches == 1
        case -1,
             1:
            let (longer, shorter) = left.count > right.count ? (left, right) : (right, left)
            var longIdx = 0
            var shortIdx = 0
            var skipped = false
            while longIdx < longer.count, shortIdx < shorter.count {
                if longer[longIdx] == shorter[shortIdx] {
                    longIdx += 1
                    shortIdx += 1
                } else {
                    if skipped {
                        return false
                    }
                    skipped = true
                    longIdx += 1
                }
            }
            return true
        default:
            return false
        }
    }
}
