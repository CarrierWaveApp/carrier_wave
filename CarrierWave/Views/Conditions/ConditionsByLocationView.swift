import Charts
import SwiftUI

/// Compares environmental conditions across grid squares using bar charts.
/// Groups snapshots by 4-char grid prefix and shows average metric values.
struct ConditionsByLocationView: View {
    // MARK: Internal

    let groupedSnapshots: [String: [EnvironmentalSnapshot]]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conditions by Location")
                .font(.headline)
                .padding(.leading, 4)

            metricPicker

            if locationData.isEmpty {
                emptyState
            } else {
                chartView
                    .frame(height: chartHeight)

                detailRows
            }
        }
    }

    // MARK: Private

    @State private var selectedMetric: ConditionsMetric = .kIndex

    private struct LocationStat: Identifiable {
        let grid: String
        let average: Double
        let min: Double
        let max: Double
        let count: Int
        var id: String { grid }
    }

    private var locationData: [LocationStat] {
        groupedSnapshots.compactMap { grid, snapshots in
            let values = snapshots.compactMap { selectedMetric.value(from: $0) }
            guard !values.isEmpty else { return nil }
            let avg = values.reduce(0, +) / Double(values.count)
            return LocationStat(
                grid: grid,
                average: avg,
                min: values.min() ?? avg,
                max: values.max() ?? avg,
                count: values.count
            )
        }
        .sorted { $0.average > $1.average }
    }

    private var chartHeight: CGFloat {
        CGFloat(max(locationData.count * 40, 100))
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableMetrics) { metric in
                    Button {
                        selectedMetric = metric
                    } label: {
                        Label(metric.rawValue, systemImage: metric.icon)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                selectedMetric == metric
                                    ? metric.color.opacity(0.2)
                                    : Color(.systemGray5)
                            )
                            .foregroundStyle(
                                selectedMetric == metric ? metric.color : .secondary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var availableMetrics: [ConditionsMetric] {
        ConditionsMetric.allCases.filter { metric in
            groupedSnapshots.values.contains { snapshots in
                snapshots.contains { metric.value(from: $0) != nil }
            }
        }
    }

    private var chartView: some View {
        Chart(locationData) { stat in
            BarMark(
                x: .value(selectedMetric.rawValue, stat.average),
                y: .value("Grid", stat.grid)
            )
            .foregroundStyle(selectedMetric.color.gradient)
            .annotation(position: .trailing) {
                Text(selectedMetric.formatValue(stat.average))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let grid = value.as(String.self) {
                        Text(grid)
                            .font(.caption)
                            .monospaced()
                    }
                }
            }
        }
    }

    private var detailRows: some View {
        VStack(spacing: 0) {
            ForEach(locationData) { stat in
                HStack {
                    Text(stat.grid)
                        .font(.caption)
                        .monospaced()
                        .fontWeight(.medium)
                        .frame(width: 50, alignment: .leading)

                    rangeBadge(stat)

                    Spacer()

                    Text("\(stat.count) samples")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func rangeBadge(_ stat: LocationStat) -> some View {
        HStack(spacing: 4) {
            Text(selectedMetric.formatValue(stat.min))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("–")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(selectedMetric.formatValue(stat.max))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No location data available")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Conditions recorded with a grid square will appear here")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}
