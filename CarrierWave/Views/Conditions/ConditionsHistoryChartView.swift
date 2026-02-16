import Charts
import SwiftUI

// MARK: - ConditionsMetric

/// Which metric to display in the conditions chart.
enum ConditionsMetric: String, CaseIterable, Identifiable {
    case kIndex = "K-Index"
    case aIndex = "A-Index"
    case solarFlux = "SFI"
    case sunspots = "Sunspots"
    case temperature = "Temp"
    case humidity = "Humidity"
    case windSpeed = "Wind"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .kIndex: "waveform"
        case .aIndex: "waveform.path"
        case .solarFlux: "sun.max.fill"
        case .sunspots: "circle.dotted"
        case .temperature: "thermometer.medium"
        case .humidity: "humidity"
        case .windSpeed: "wind"
        }
    }

    var color: Color {
        switch self {
        case .kIndex: .orange
        case .aIndex: .purple
        case .solarFlux: .yellow
        case .sunspots: .orange
        case .temperature: .red
        case .humidity: .cyan
        case .windSpeed: .teal
        }
    }

    var isSolar: Bool {
        switch self {
        case .kIndex,
             .aIndex,
             .solarFlux,
             .sunspots: true
        default: false
        }
    }

    func value(from snapshot: EnvironmentalSnapshot) -> Double? {
        switch self {
        case .kIndex: snapshot.solarKIndex
        case .aIndex: snapshot.solarAIndex.map(Double.init)
        case .solarFlux: snapshot.solarFlux
        case .sunspots: snapshot.solarSunspots.map(Double.init)
        case .temperature: snapshot.weatherTemperatureF
        case .humidity: snapshot.weatherHumidity.map(Double.init)
        case .windSpeed: snapshot.weatherWindSpeed
        }
    }

    func formatValue(_ value: Double) -> String {
        switch self {
        case .kIndex: String(format: "%.1f", value)
        case .aIndex: "\(Int(value))"
        case .solarFlux: "\(Int(value))"
        case .sunspots: "\(Int(value))"
        case .temperature: UnitFormatter.temperature(value)
        case .humidity: "\(Int(value))%"
        case .windSpeed: UnitFormatter.windSpeed(value, direction: nil)
        }
    }
}

// MARK: - ConditionsHistoryChartView

/// Time-series chart showing environmental conditions over a date range.
/// Plots data points from LoggingSession and ActivationMetadata snapshots.
struct ConditionsHistoryChartView: View {
    // MARK: Internal

    let snapshots: [EnvironmentalSnapshot]
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.leading, 4)

            metricPicker

            if filteredData.isEmpty {
                emptyState
            } else {
                chartView
                    .frame(height: 200)

                statsRow
            }
        }
    }

    // MARK: Private

    @State private var selectedMetric: ConditionsMetric = .kIndex

    /// Data points averaged per calendar day (UTC) to reduce clutter from
    /// multiple sessions on the same day. Plotted at noon UTC for each day.
    private var filteredData: [(date: Date, value: Double)] {
        let raw = snapshots.compactMap { snapshot -> (key: String, value: Double)? in
            guard let value = selectedMetric.value(from: snapshot) else {
                return nil
            }
            return (key: Self.dayKey(snapshot.timestamp), value: value)
        }

        // Group by day and average
        var grouped: [String: [Double]] = [:]
        for point in raw {
            grouped[point.key, default: []].append(point.value)
        }

        return grouped.map { key, values in
            let avg = values.reduce(0, +) / Double(values.count)
            return (date: Self.dateFromDayKey(key), value: avg)
        }
        .sorted { $0.date < $1.date }
    }

    /// Raw sample count for the selected metric (before day-averaging).
    private var rawSampleCount: Int {
        snapshots.filter { selectedMetric.value(from: $0) != nil }.count
    }

    /// Only show metrics that have data in the snapshots.
    private var availableMetrics: [ConditionsMetric] {
        ConditionsMetric.allCases.filter { metric in
            snapshots.contains { metric.value(from: $0) != nil }
        }
    }

    private var averageValue: Double? {
        guard !filteredData.isEmpty else {
            return nil
        }
        let sum = filteredData.reduce(0.0) { $0 + $1.value }
        return sum / Double(filteredData.count)
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

    private var chartView: some View {
        Chart {
            ForEach(filteredData, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(selectedMetric.rawValue, point.value)
                )
                .foregroundStyle(selectedMetric.color)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value(selectedMetric.rawValue, point.value)
                )
                .foregroundStyle(selectedMetric.color)
                .symbolSize(20)
            }

            if let avg = averageValue {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(selectedMetric.color.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .trailing, alignment: .trailing) {
                        Text("avg")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 9))
                    }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            if let minVal = filteredData.map(\.value).min() {
                miniStat(
                    label: "Min",
                    value: selectedMetric.formatValue(minVal)
                )
            }
            if let avg = averageValue {
                miniStat(
                    label: "Avg",
                    value: selectedMetric.formatValue(avg)
                )
            }
            if let maxVal = filteredData.map(\.value).max() {
                miniStat(
                    label: "Max",
                    value: selectedMetric.formatValue(maxVal)
                )
            }

            Spacer()

            Text("\(rawSampleCount) samples")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedMetric.icon)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No \(selectedMetric.rawValue) data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Day Averaging Helpers

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func dateFromDayKey(_ key: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let startOfDay = formatter.date(from: key) ?? Date()
        // Plot at noon UTC for visual centering
        return startOfDay.addingTimeInterval(12 * 3_600)
    }
}
