// Activation Statistics
//
// Pure stats computation for POTA activations. Computes distance,
// timing, band/mode distribution, RST, and entity statistics.

import CoreLocation
import Foundation

// MARK: - ActivationStatistics

struct ActivationStatistics {
    let distance: DistanceStatistics?
    let timing: TimingStatistics?
    let bandDistribution: [BandDistribution]
    let modeDistribution: [ModeDistribution]
    let rst: RSTStatistics?
    let uniqueStates: Int
    let uniqueGrids: Int

    static func compute(
        from activation: POTAActivation,
        metadata: ActivationMetadata? = nil
    ) -> ActivationStatistics {
        let qsos = activation.qsos
        let distances = computeDistances(qsos)
        let intervals = computeIntervals(qsos)

        return ActivationStatistics(
            distance: DistanceStatistics.compute(from: distances),
            timing: TimingStatistics.compute(
                from: intervals, qsos: qsos
            ),
            bandDistribution: computeBandDistribution(qsos),
            modeDistribution: computeModeDistribution(qsos),
            rst: RSTStatistics.compute(from: qsos),
            uniqueStates: Set(qsos.compactMap(\.state)).count,
            uniqueGrids: Set(
                qsos.compactMap(\.theirGrid)
                    .map { String($0.prefix(4)) }
            ).count
        )
    }
}

// MARK: - DistanceStatistics

struct DistanceStatistics {
    let mean: Double
    let median: Double
    let stdDev: Double
    let min: Double
    let max: Double
    let p10: Double
    let p25: Double
    let p75: Double
    let p90: Double
    let iqr: Double
    let coefficientOfVariation: Double
    let skewness: Double
    let count: Int

    static func compute(from distances: [Double]) -> DistanceStatistics? {
        guard distances.count >= 2 else {
            return nil
        }
        let sorted = distances.sorted()
        let count = Double(sorted.count)
        let sum = sorted.reduce(0, +)
        let mean = sum / count

        let variance = sorted.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / count
        let stdDev = sqrt(variance)

        let skew: Double = stdDev > 0
            ? sorted.reduce(0.0) {
                $0 + pow(($1 - mean) / stdDev, 3)
            } / count
            : 0

        let p25 = percentile(sorted, at: 0.25)
        let p75 = percentile(sorted, at: 0.75)

        return DistanceStatistics(
            mean: mean,
            median: percentile(sorted, at: 0.5),
            stdDev: stdDev,
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            p10: percentile(sorted, at: 0.10),
            p25: p25,
            p75: p75,
            p90: percentile(sorted, at: 0.90),
            iqr: p75 - p25,
            coefficientOfVariation: mean > 0 ? stdDev / mean : 0,
            skewness: skew,
            count: sorted.count
        )
    }
}

// MARK: - TimingStatistics

struct TimingStatistics {
    // MARK: Internal

    let meanIntervalSeconds: Double
    let medianIntervalSeconds: Double
    let stdDevIntervalSeconds: Double
    let minIntervalSeconds: Double
    let p25IntervalSeconds: Double
    let p75IntervalSeconds: Double
    let maxIntervalSeconds: Double
    let peak15MinRate: Double // QSOs in best 15-min window

    static func compute(
        from intervals: [TimeInterval],
        qsos: [QSO]
    ) -> TimingStatistics? {
        guard !intervals.isEmpty else {
            return nil
        }
        let sorted = intervals.sorted()
        let count = Double(sorted.count)
        let sum = sorted.reduce(0, +)
        let mean = sum / count
        let variance = sorted.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / count

        return TimingStatistics(
            meanIntervalSeconds: mean,
            medianIntervalSeconds: percentile(sorted, at: 0.5),
            stdDevIntervalSeconds: sqrt(variance),
            minIntervalSeconds: sorted.first ?? 0,
            p25IntervalSeconds: percentile(sorted, at: 0.25),
            p75IntervalSeconds: percentile(sorted, at: 0.75),
            maxIntervalSeconds: sorted.last ?? 0,
            peak15MinRate: computePeak15MinRate(qsos: qsos)
        )
    }

    // MARK: Private

    private static func computePeak15MinRate(qsos: [QSO]) -> Double {
        let timestamps = qsos.map(\.timestamp).sorted()
        guard timestamps.count >= 2 else {
            return Double(timestamps.count)
        }

        let window: TimeInterval = 15 * 60
        var bestCount = 0
        for (i, start) in timestamps.enumerated() {
            let end = start.addingTimeInterval(window)
            let count = timestamps[i...].prefix(while: { $0 <= end }).count
            bestCount = max(bestCount, count)
        }
        return Double(bestCount)
    }
}

// MARK: - BandDistribution

struct BandDistribution: Identifiable {
    let band: String
    let count: Int
    let percentage: Double

    var id: String {
        band
    }
}

// MARK: - ModeDistribution

struct ModeDistribution: Identifiable {
    let mode: String
    let count: Int
    let percentage: Double

    var id: String {
        mode
    }
}

// MARK: - RSTComponentBucket

struct RSTComponentBucket: Identifiable {
    let value: Int
    let count: Int

    var id: Int {
        value
    }
}

// MARK: - ParsedRST

private struct ParsedRST {
    let readability: Int // 1-5
    let signal: Int // 1-9
    let tone: Int? // 1-9, CW only
}

// MARK: - RSTStatistics

struct RSTStatistics {
    // MARK: Internal

    let sentR: [RSTComponentBucket]
    let sentS: [RSTComponentBucket]
    let sentT: [RSTComponentBucket] // CW only; empty for phone
    let receivedR: [RSTComponentBucket]
    let receivedS: [RSTComponentBucket]
    let receivedT: [RSTComponentBucket]

    static func compute(from qsos: [QSO]) -> RSTStatistics? {
        let sentParsed = qsos.compactMap { $0.rstSent.flatMap(parseRST) }
        let recvParsed = qsos.compactMap { $0.rstReceived.flatMap(parseRST) }
        guard !sentParsed.isEmpty || !recvParsed.isEmpty else {
            return nil
        }
        return RSTStatistics(
            sentR: bucketize(sentParsed.map(\.readability)),
            sentS: bucketize(sentParsed.map(\.signal)),
            sentT: bucketize(sentParsed.compactMap(\.tone)),
            receivedR: bucketize(recvParsed.map(\.readability)),
            receivedS: bucketize(recvParsed.map(\.signal)),
            receivedT: bucketize(recvParsed.compactMap(\.tone))
        )
    }

    // MARK: Private

    private static func parseRST(_ rst: String) -> ParsedRST? {
        let digits = rst.compactMap(\.wholeNumberValue)
        guard digits.count >= 2 else {
            return nil
        }
        let tone = digits.count >= 3 ? digits[2] : nil
        return ParsedRST(readability: digits[0], signal: digits[1], tone: tone)
    }

    private static func bucketize(_ values: [Int]) -> [RSTComponentBucket] {
        guard !values.isEmpty else {
            return []
        }
        var counts: [Int: Int] = [:]
        for val in values {
            counts[val, default: 0] += 1
        }
        return counts.map { RSTComponentBucket(value: $0.key, count: $0.value) }
            .sorted { $0.value > $1.value }
    }
}

// MARK: - Helpers

private func percentile(_ sorted: [Double], at pct: Double) -> Double {
    guard !sorted.isEmpty else {
        return 0
    }
    let index = pct * Double(sorted.count - 1)
    let lower = Int(floor(index))
    let upper = min(lower + 1, sorted.count - 1)
    let fraction = index - Double(lower)
    return sorted[lower] + fraction * (sorted[upper] - sorted[lower])
}

private func computeDistances(_ qsos: [QSO]) -> [Double] {
    qsos.compactMap { qso in
        guard let myGrid = qso.myGrid, myGrid.count >= 4,
              let theirGrid = qso.theirGrid, theirGrid.count >= 4,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }
        let fromLoc = CLLocation(latitude: myCoord.latitude, longitude: myCoord.longitude)
        let toLoc = CLLocation(latitude: theirCoord.latitude, longitude: theirCoord.longitude)
        return fromLoc.distance(from: toLoc) / 1_000.0
    }
}

private func computeIntervals(_ qsos: [QSO]) -> [TimeInterval] {
    let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
    guard sorted.count >= 2 else {
        return []
    }
    return zip(sorted, sorted.dropFirst()).map {
        $1.timestamp.timeIntervalSince($0.timestamp)
    }
}

private func computeBandDistribution(_ qsos: [QSO]) -> [BandDistribution] {
    let total = Double(qsos.count)
    guard total > 0 else {
        return []
    }
    var counts: [String: Int] = [:]
    for qso in qsos {
        counts[qso.band, default: 0] += 1
    }
    return counts.map { band, count in
        BandDistribution(
            band: band,
            count: count,
            percentage: Double(count) / total * 100
        )
    }.sorted { $0.count > $1.count }
}

private func computeModeDistribution(_ qsos: [QSO]) -> [ModeDistribution] {
    let total = Double(qsos.count)
    guard total > 0 else {
        return []
    }
    var counts: [String: Int] = [:]
    for qso in qsos {
        counts[qso.mode, default: 0] += 1
    }
    return counts.map { mode, count in
        ModeDistribution(
            mode: mode,
            count: count,
            percentage: Double(count) / total * 100
        )
    }.sorted { $0.count > $1.count }
}
