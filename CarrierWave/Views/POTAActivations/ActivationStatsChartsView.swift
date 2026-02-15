// Activation Stats Charts View
//
// Swift Charts for the activation detail view when Professional
// Statistician Mode is enabled. Shows band distribution, QSO rate
// over time, and distance distribution.

import Charts
import CoreLocation
import SwiftUI

// MARK: - ActivationStatsChartsView

struct ActivationStatsChartsView: View {
    let stats: ActivationStatistics
    let qsos: [QSO]

    var body: some View {
        VStack(spacing: 16) {
            if !stats.bandDistribution.isEmpty {
                bandChart
            }
            if qsos.count >= 2 {
                rateChart
            }
            if let distance = stats.distance, distance.count >= 3 {
                distanceChart
            }
        }
    }
}

// MARK: - Band Distribution Chart

private extension ActivationStatsChartsView {
    var bandChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Band Distribution")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Chart(stats.bandDistribution) { item in
                BarMark(
                    x: .value("Count", item.count),
                    y: .value("Band", item.band)
                )
                .foregroundStyle(bandColor(item.band))
                .annotation(position: .trailing, spacing: 4) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let band = value.as(String.self) {
                            Text(band)
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: chartHeight(for: stats.bandDistribution.count))
        }
    }

    func chartHeight(for itemCount: Int) -> CGFloat {
        CGFloat(max(itemCount, 1)) * 28 + 8
    }

    func bandColor(_ band: String) -> Color {
        switch band {
        case "160m": .red
        case "80m": .orange
        case "60m": .yellow
        case "40m": .green
        case "30m": .teal
        case "20m": .blue
        case "17m": .indigo
        case "15m": .purple
        case "12m": .pink
        case "10m": .mint
        case "6m": .cyan
        case "2m": .brown
        default: .gray
        }
    }
}

// MARK: - QSO Rate Chart

private extension ActivationStatsChartsView {
    var rateChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("QSO Rate (rolling 15 min)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Chart(rateDataPoints) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Rate", point.rate)
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.monotone)
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Rate", point.rate)
                )
                .foregroundStyle(.purple.opacity(0.15))
                .interpolationMethod(.monotone)
            }
            .chartYAxisLabel("QSOs/hr")
            .frame(height: 120)
        }
    }

    var rateDataPoints: [RatePoint] {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2,
              let first = sorted.first?.timestamp,
              let last = sorted.last?.timestamp
        else {
            return []
        }

        let totalSpan = last.timeIntervalSince(first)
        guard totalSpan > 0 else {
            return []
        }

        let stepCount = min(30, max(5, sorted.count))
        let step = totalSpan / Double(stepCount)
        let window: TimeInterval = 15 * 60

        var points: [RatePoint] = []
        for i in 0 ... stepCount {
            let time = first.addingTimeInterval(Double(i) * step)
            let windowStart = time.addingTimeInterval(-window / 2)
            let windowEnd = time.addingTimeInterval(window / 2)
            let count = sorted.filter {
                $0.timestamp >= windowStart && $0.timestamp <= windowEnd
            }.count
            let rate = Double(count) / (window / 3_600)
            points.append(RatePoint(time: time, rate: rate))
        }
        return points
    }
}

// MARK: - Distance Distribution Chart

private extension ActivationStatsChartsView {
    var distanceChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Distance Distribution")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Chart(distanceBuckets) { bucket in
                BarMark(
                    x: .value("Distance", bucket.label),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(.teal.gradient)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(size: 8))
                                .rotationEffect(.degrees(-45))
                        }
                    }
                }
            }
            .frame(height: 120)
        }
    }

    var distanceBuckets: [DistanceBucket] {
        let distances = qsos.compactMap { qso -> Double? in
            guard let myGrid = qso.myGrid, myGrid.count >= 4,
                  let theirGrid = qso.theirGrid, theirGrid.count >= 4,
                  let myCoord = MaidenheadConverter.coordinate(from: myGrid),
                  let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
            else {
                return nil
            }
            let fromLoc = CLLocation(
                latitude: myCoord.latitude, longitude: myCoord.longitude
            )
            let toLoc = CLLocation(
                latitude: theirCoord.latitude, longitude: theirCoord.longitude
            )
            return fromLoc.distance(from: toLoc) / 1_000.0
        }
        guard !distances.isEmpty else {
            return []
        }

        let maxDist = distances.max() ?? 1
        let bucketCount = min(8, max(3, distances.count / 2))
        let bucketSize = maxDist / Double(bucketCount)
        guard bucketSize > 0 else {
            return []
        }

        var buckets: [DistanceBucket] = []
        for i in 0 ..< bucketCount {
            let low = Double(i) * bucketSize
            let high = Double(i + 1) * bucketSize
            let count = distances.filter { $0 >= low && $0 < high }.count
            let label = "\(Int(low))-\(Int(high))km"
            buckets.append(DistanceBucket(label: label, count: count))
        }
        return buckets
    }
}

// MARK: - RatePoint

private struct RatePoint: Identifiable {
    let time: Date
    let rate: Double

    var id: Date {
        time
    }
}

// MARK: - DistanceBucket

private struct DistanceBucket: Identifiable {
    let label: String
    let count: Int

    var id: String {
        label
    }
}
