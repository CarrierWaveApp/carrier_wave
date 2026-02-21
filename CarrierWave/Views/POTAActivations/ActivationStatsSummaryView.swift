// Activation Stats Summary View
//
// Compact two-column grid of computed statistics for the activation
// detail view when Professional Statistician Mode is enabled.

import SwiftUI

// MARK: - ActivationStatsSummaryView

struct ActivationStatsSummaryView: View {
    // MARK: Internal

    let stats: ActivationStatistics

    var body: some View {
        let _ = useMetricUnits
        VStack(alignment: .leading, spacing: 12) {
            if let distance = stats.distance {
                distanceSection(distance)
            }
            if let timing = stats.timing {
                timingSection(timing)
            }
            if let rst = stats.rst {
                rstSection(rst)
            }
            entitySection
        }
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false
}

// MARK: - Sections

private extension ActivationStatsSummaryView {
    func distanceSection(_ dist: DistanceStatistics) -> some View {
        StatSection(title: "Distance") {
            StatRow(label: "Mean", value: UnitFormatter.distance(dist.mean))
            StatRow(
                label: "Median",
                value: UnitFormatter.distance(dist.median)
            )
            StatRow(
                label: "Std Dev",
                value: UnitFormatter.distance(dist.stdDev)
            )
            StatRow(label: "Min", value: UnitFormatter.distance(dist.min))
            StatRow(label: "Max", value: UnitFormatter.distance(dist.max))
            StatRow(label: "IQR", value: UnitFormatter.distance(dist.iqr))
            StatRow(
                label: "CV",
                value: String(format: "%.2f", dist.coefficientOfVariation)
            )
            StatRow(
                label: "Skewness",
                value: String(format: "%.2f", dist.skewness)
            )
        }
    }

    func timingSection(_ timing: TimingStatistics) -> some View {
        StatSection(title: "Timing") {
            StatRow(
                label: "Mean interval",
                value: formatSeconds(timing.meanIntervalSeconds)
            )
            StatRow(
                label: "Median interval",
                value: formatSeconds(timing.medianIntervalSeconds)
            )
            StatRow(
                label: "Interval σ",
                value: formatSeconds(timing.stdDevIntervalSeconds)
            )
            StatRow(
                label: "Peak 15-min",
                value: String(format: "%.0f QSOs", timing.peak15MinRate)
            )
        }
    }

    func rstSection(_ rst: RSTStatistics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RST")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if !rst.sentR.isEmpty {
                rstComponentRow("Sent R", buckets: rst.sentR)
                rstComponentRow("Sent S", buckets: rst.sentS)
            }
            if !rst.sentT.isEmpty {
                rstComponentRow("Sent T", buckets: rst.sentT)
            }
            if !rst.receivedR.isEmpty {
                rstComponentRow("Rcvd R", buckets: rst.receivedR)
                rstComponentRow("Rcvd S", buckets: rst.receivedS)
            }
            if !rst.receivedT.isEmpty {
                rstComponentRow("Rcvd T", buckets: rst.receivedT)
            }
        }
    }

    func rstComponentRow(
        _ label: String,
        buckets: [RSTComponentBucket]
    ) -> some View {
        let sorted = Array(
            buckets.sorted { $0.value > $1.value }.prefix(6)
        )
        let total = sorted.reduce(0) { $0 + $1.count }
        let radius: CGFloat = 4
        return HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                let widths = rstBarWidths(
                    sorted, total: total, container: geo.size.width
                )
                HStack(spacing: 0) {
                    ForEach(
                        Array(sorted.enumerated()),
                        id: \.element.id
                    ) { idx, bucket in
                        rstBarSegment(
                            bucket: bucket, width: widths[idx],
                            radius: radius,
                            isFirst: idx == 0,
                            isLast: idx == sorted.count - 1
                        )
                    }
                }
            }
            .frame(height: 18)
        }
    }

    func rstBarSegment(
        bucket: RSTComponentBucket, width: CGFloat, radius: CGFloat,
        isFirst: Bool, isLast: Bool
    ) -> some View {
        Text("\(bucket.value)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: width, height: 18)
            .background(rstBarColor(bucket.value).opacity(0.7))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: isFirst ? radius : 0,
                    bottomLeadingRadius: isFirst ? radius : 0,
                    bottomTrailingRadius: isLast ? radius : 0,
                    topTrailingRadius: isLast ? radius : 0
                )
            )
    }

    /// Compute bar widths with a minimum, scaling down if total exceeds container.
    func rstBarWidths(
        _ sorted: [RSTComponentBucket], total: Int, container: CGFloat
    ) -> [CGFloat] {
        let minW: CGFloat = 20
        let raw = sorted.map { bucket in
            max(CGFloat(bucket.count) / CGFloat(max(total, 1)) * container, minW)
        }
        let rawTotal = raw.reduce(0, +)
        guard rawTotal > container else {
            return raw
        }
        let scale = container / rawTotal
        return raw.map { $0 * scale }
    }

    func rstBarColor(_ value: Int) -> Color {
        switch value {
        case 9: .green
        case 8: .teal
        case 7: .blue
        case 6: .indigo
        case 5: .purple
        case 4: .orange
        case 3: .red
        default: .gray
        }
    }

    var entitySection: some View {
        StatSection(title: "Entities") {
            if stats.uniqueStates > 0 {
                StatRow(label: "States", value: "\(stats.uniqueStates)")
            }
            if stats.uniqueGrids > 0 {
                StatRow(label: "Grids", value: "\(stats.uniqueGrids)")
            }
        }
    }

    func formatSeconds(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

// MARK: - StatSection

private struct StatSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                ],
                spacing: 4
            ) {
                content()
            }
        }
    }
}

// MARK: - StatRow

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}
