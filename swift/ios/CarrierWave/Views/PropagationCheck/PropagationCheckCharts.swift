import CarrierWaveData
import Charts
import SwiftUI

// MARK: - PropagationCheckTimelineChart

/// Spots-per-minute line chart bucketed across the session window.
struct PropagationCheckTimelineChart: View {
    let spots: [PropagationSpotEntry]
    let startedAt: Date
    let endedAt: Date

    var body: some View {
        let buckets = PropagationCheckStatistics.timeline(
            spots: spots, startedAt: startedAt, endedAt: endedAt
        )
        VStack(alignment: .leading, spacing: 8) {
            Text("Spots per Minute")
                .font(.headline)
            if buckets.isEmpty {
                Text("Not enough data for a timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(buckets) { bucket in
                    LineMark(
                        x: .value("Minute", bucket.minute),
                        y: .value("Spots", bucket.count)
                    )
                    .interpolationMethod(.monotone)
                }
                .frame(height: 120)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - PropagationCheckDistanceHistogram

/// Distance-bucketed histogram of skimmer distances from the operator grid.
struct PropagationCheckDistanceHistogram: View {
    let spots: [PropagationSpotEntry]
    let userGrid: String

    var body: some View {
        let buckets = PropagationCheckStatistics.distanceHistogram(spots: spots, userGrid: userGrid)
        let total = buckets.reduce(into: 0) { $0 += $1.count }
        VStack(alignment: .leading, spacing: 8) {
            Text("Distance Histogram (km)")
                .font(.headline)
            if total == 0 {
                Text("No grid-resolved skimmer distances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Range", bucket.label),
                        y: .value("Count", bucket.count)
                    )
                }
                .frame(height: 140)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
