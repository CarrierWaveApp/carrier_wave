import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - PropagationCheckStatistics

/// Pure statistics computation for propagation check artifacts. No I/O, no
/// SwiftData — runs from a snapshot of spots + the user's grid.
nonisolated enum PropagationCheckStatistics {
    // MARK: Internal

    // MARK: - Headline

    nonisolated struct Headline: Equatable {
        var totalSpots: Int
        var uniqueSkimmers: Int
        var bandsWithActivity: [String]
        var maxDistanceKm: Double
        var peakSNRdB: Double
    }

    // MARK: - Per-band breakdown

    nonisolated struct BandBreakdownRow: Identifiable, Equatable {
        let band: String
        let spotCount: Int
        let uniqueSkimmers: Int
        let maxDistanceKm: Double
        let medianSNRdB: Double
        let peakSNRdB: Double

        var id: String {
            band
        }
    }

    // MARK: - Geographic breakdowns

    nonisolated struct GeographicBucket: Identifiable, Equatable {
        let name: String
        let spotCount: Int

        var id: String {
            name
        }
    }

    // MARK: - Spots-per-minute timeline

    nonisolated struct TimelineBucket: Identifiable, Equatable {
        let minute: Date
        let count: Int

        var id: Date {
            minute
        }
    }

    // MARK: - Distance histogram

    nonisolated struct HistogramBucket: Identifiable, Equatable {
        let label: String
        let lowerKm: Double
        let upperKm: Double
        let count: Int

        var id: String {
            label
        }
    }

    static func compute(spots: [PropagationSpotEntry], userGrid: String) -> Headline {
        let total = spots.count
        let unique = Set(spots.map { $0.skimmerCall.uppercased() }).count
        let bandsRaw = spots.compactMap(\.band).filter { !$0.isEmpty }
        let bands = Array(Set(bandsRaw)).sorted { lhs, rhs in
            let order = standardBandOrder
            return (order.firstIndex(of: lhs) ?? Int.max) < (order.firstIndex(of: rhs) ?? Int.max)
        }
        let maxDist = spots.compactMap { spot -> Double? in
            guard let grid = spot.skimmerGrid else {
                return nil
            }
            return distanceKm(from: userGrid, to: grid)
        }.max() ?? 0
        let peakSNR = spots.compactMap(\.snrDB).max() ?? 0

        return Headline(
            totalSpots: total,
            uniqueSkimmers: unique,
            bandsWithActivity: bands,
            maxDistanceKm: maxDist,
            peakSNRdB: peakSNR
        )
    }

    static func bandBreakdown(spots: [PropagationSpotEntry], userGrid: String) -> [BandBreakdownRow] {
        let grouped = Dictionary(grouping: spots) { $0.band ?? "" }.filter { !$0.key.isEmpty }
        return grouped.map { band, spots in
            let distances = spots.compactMap { spot -> Double? in
                guard let grid = spot.skimmerGrid else {
                    return nil
                }
                return distanceKm(from: userGrid, to: grid)
            }
            let snrs = spots.compactMap(\.snrDB).sorted()
            return BandBreakdownRow(
                band: band,
                spotCount: spots.count,
                uniqueSkimmers: Set(spots.map { $0.skimmerCall.uppercased() }).count,
                maxDistanceKm: distances.max() ?? 0,
                medianSNRdB: median(snrs) ?? 0,
                peakSNRdB: snrs.max() ?? 0
            )
        }.sorted { lhs, rhs in
            (standardBandOrder.firstIndex(of: lhs.band) ?? Int.max)
                < (standardBandOrder.firstIndex(of: rhs.band) ?? Int.max)
        }
    }

    static func continentBreakdown(spots: [PropagationSpotEntry]) -> [GeographicBucket] {
        let grouped = Dictionary(grouping: spots.compactMap { spot in
            spot.skimmerGrid.flatMap(continent(forGrid:))
        }) { $0 }
        return grouped.map { name, list in
            GeographicBucket(name: name, spotCount: list.count)
        }.sorted { $0.spotCount > $1.spotCount }
    }

    static func cqZoneBreakdown(spots: [PropagationSpotEntry]) -> [GeographicBucket] {
        let grouped = Dictionary(grouping: spots.compactMap { spot in
            spot.skimmerGrid.flatMap(cqZone(forGrid:))
        }) { $0 }
        return grouped.map { name, list in
            GeographicBucket(name: name, spotCount: list.count)
        }.sorted { lhs, rhs in
            // Sort numerically by zone number when prefix is "Zone N".
            let lhsNum = Int(lhs.name.replacingOccurrences(of: "Zone ", with: "")) ?? 0
            let rhsNum = Int(rhs.name.replacingOccurrences(of: "Zone ", with: "")) ?? 0
            return lhsNum < rhsNum
        }
    }

    static func timeline(spots: [PropagationSpotEntry], startedAt: Date, endedAt: Date) -> [TimelineBucket] {
        guard !spots.isEmpty else {
            return []
        }
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.dateInterval(of: .minute, for: startedAt)?.start ?? startedAt
        let end = calendar.dateInterval(of: .minute, for: endedAt)?.start ?? endedAt
        guard end >= start else {
            return []
        }

        var buckets: [Date: Int] = [:]
        var cursor = start
        while cursor <= end {
            buckets[cursor] = 0
            cursor = calendar.date(byAdding: .minute, value: 1, to: cursor) ?? cursor.addingTimeInterval(60)
        }
        for spot in spots {
            let bucket = calendar.dateInterval(of: .minute, for: spot.timestamp)?.start ?? spot.timestamp
            buckets[bucket, default: 0] += 1
        }
        return buckets.map { TimelineBucket(minute: $0.key, count: $0.value) }
            .sorted { $0.minute < $1.minute }
    }

    static func distanceHistogram(spots: [PropagationSpotEntry], userGrid: String) -> [HistogramBucket] {
        let edges: [Double] = [0, 500, 1_500, 3_000, 6_000, 10_000, 15_000, 25_000]
        let labels = ["<500", "500–1500", "1500–3000", "3000–6000", "6000–10000", "10000–15000", "15000+"]
        var counts = [Int](repeating: 0, count: labels.count)
        for spot in spots {
            guard let grid = spot.skimmerGrid,
                  let distanceKilometers = distanceKm(from: userGrid, to: grid)
            else {
                continue
            }
            for idx in 0 ..< (edges.count - 1) {
                if distanceKilometers < edges[idx + 1] {
                    counts[idx] += 1
                    break
                } else if idx == edges.count - 2 {
                    counts[idx] += 1
                }
            }
        }
        return zip(labels.indices, labels).map { idx, label in
            HistogramBucket(
                label: label,
                lowerKm: edges[idx],
                upperKm: idx + 1 < edges.count ? edges[idx + 1] : .infinity,
                count: counts[idx]
            )
        }
    }

    // MARK: Private

    private static let standardBandOrder = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm",
    ]

    private static func median(_ sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else {
            return nil
        }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func distanceKm(from origin: String, to destination: String) -> Double? {
        MaidenheadConverter.distanceKm(from: origin, to: destination)
    }

    private static func continent(forGrid grid: String) -> String? {
        guard let coord = MaidenheadConverter.coordinate(from: grid) else {
            return nil
        }
        // Crude box-based continent classification — good enough for histogramming.
        let lat = coord.latitude
        let lon = coord.longitude
        switch (lat, lon) {
        case let (lat, lon) where lat >= 7 && lat <= 84 && lon >= -169 && lon <= -50:
            return "North America"
        case let (lat, lon) where lat >= -55 && lat < 12 && lon >= -82 && lon <= -34:
            return "South America"
        case let (lat, lon) where lat >= 35 && lat <= 72 && lon >= -10 && lon <= 60:
            return "Europe"
        case let (lat, lon) where lat >= -35 && lat < 37 && lon >= -18 && lon <= 52:
            return "Africa"
        case let (lat, lon) where lat >= -10 && lat <= 80 && lon > 60 && lon <= 180:
            return "Asia"
        case let (lat, lon) where lat >= -50 && lat < -10 && lon >= 110 && lon <= 180:
            return "Oceania"
        case let (lat, _) where lat < -55:
            return "Antarctica"
        default:
            return "Other"
        }
    }

    private static func cqZone(forGrid grid: String) -> String? {
        // Approximate zone bucketing by longitude bands. Real CQ zone math is
        // complex; this is good enough for relative breakdown UX. Refinable later.
        guard let coord = MaidenheadConverter.coordinate(from: grid) else {
            return nil
        }
        let lon = coord.longitude
        let zone: Int = {
            // 40 zones roughly, 9° each.
            let normalized = (lon + 180).truncatingRemainder(dividingBy: 360)
            return Int(normalized / 9) + 1
        }()
        return "Zone \(zone)"
    }
}
