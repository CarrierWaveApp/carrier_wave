import UIKit

// MARK: - HeardStation

/// One Heard row: a station, collapsed per callsign — the latest spot
/// wins the row; the rest ride along as history for the peek sheet
/// (spec §13). Never render a raw per-spot feed.
struct HeardStation: Identifiable {
    let callsign: String
    /// Newest spot for this callsign (any band).
    let latest: EnrichedSpot
    /// All session spots for the callsign, newest first.
    let history: [EnrichedSpot]

    var id: String {
        callsign
    }

    var heardCount: Int {
        history.count
    }
}

// MARK: - HeardBucket

/// Time-bucket sticky headers (§13) — replace Scope's frequency headers.
enum HeardBucket: Int, CaseIterable, Identifiable {
    case justNow
    case recent
    case earlier

    // MARK: Internal

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .justNow: "Just now"
        case .recent: "Last 15 min"
        case .earlier: "Earlier"
        }
    }

    static func bucket(for spotted: Date, now: Date = Date()) -> HeardBucket {
        let age = now.timeIntervalSince(spotted)
        if age < BandScopeTunables.bucketJustNowSeconds {
            return .justNow
        }
        if age < BandScopeTunables.bucketRecentSeconds {
            return .recent
        }
        return .earlier
    }
}

// MARK: - HeardAggregation

/// Pure Heard-lens assembly. Sort integrity is non-negotiable (§13):
/// strictly reverse-chronological by last-heard — never re-ranked by
/// priority. Needs get the shelf, not the top of the feed.
enum HeardAggregation {
    /// Collapse per callsign (latest wins), drop busted-copy suspects
    /// entirely (§10 — they only matter in the frequency domain), and
    /// sort newest-first.
    static func stations(
        from spots: [EnrichedSpot],
        excluding bustedIDs: Set<String> = []
    ) -> [HeardStation] {
        var byCallsign: [String: [EnrichedSpot]] = [:]
        for spot in spots where !bustedIDs.contains(spot.id) {
            byCallsign[spot.spot.callsign.uppercased(), default: []].append(spot)
        }
        return byCallsign
            .map { callsign, group in
                let sorted = group.sorted { $0.spot.timestamp > $1.spot.timestamp }
                return HeardStation(callsign: callsign, latest: sorted[0], history: sorted)
            }
            .sorted { $0.latest.spot.timestamp > $1.latest.spot.timestamp }
    }

    /// Group stations into their sticky-header buckets, preserving order.
    static func bucketed(
        _ stations: [HeardStation],
        now: Date = Date()
    ) -> [(bucket: HeardBucket, stations: [HeardStation])] {
        var groups: [HeardBucket: [HeardStation]] = [:]
        for station in stations {
            groups[HeardBucket.bucket(for: station.latest.spot.timestamp, now: now), default: []]
                .append(station)
        }
        return HeardBucket.allCases.compactMap { bucket in
            groups[bucket].map { (bucket: bucket, stations: $0) }
        }
    }
}
