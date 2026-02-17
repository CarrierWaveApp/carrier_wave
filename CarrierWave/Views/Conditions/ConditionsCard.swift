import Charts
import SwiftData
import SwiftUI

/// Dashboard card showing a compact sparkline of recent conditions
/// with the latest solar/weather snapshot. Taps through to full history.
struct ConditionsCard: View {
    // MARK: Internal

    let tourState: TourState

    var body: some View {
        NavigationLink {
            ConditionsHistoryView(tourState: tourState)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .task {
            await loadRecentData()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var snapshots: [EnvironmentalSnapshot] = []
    @State private var isLoading = true

    private let dataActor = EnvironmentalDataActor()

    /// K-index data averaged per calendar day (UTC) to reduce sparkline clutter.
    private var kIndexData: [(date: Date, value: Double)] {
        let raw = snapshots.compactMap { snapshot -> (key: String, value: Double)? in
            guard let k = snapshot.solarKIndex else {
                return nil
            }
            return (key: Self.dayKey(snapshot.timestamp), value: k)
        }

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

    private var latestSolarSnapshot: EnvironmentalSnapshot? {
        snapshots.last { $0.hasSolarData }
    }

    private var latestWeatherSnapshot: EnvironmentalSnapshot? {
        snapshots.last { $0.hasWeatherData }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conditions")
                    .font(.headline)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if snapshots.isEmpty {
                emptyState
            } else {
                metricsRow
                sparklineChart
                    .frame(height: 50)
                timestampFooter
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var metricsRow: some View {
        HStack(spacing: 8) {
            if let latest = latestSolarSnapshot {
                if let k = latest.solarKIndex {
                    metricPill(
                        icon: "waveform",
                        label: "K",
                        value: String(format: "%.1f", k),
                        color: kIndexColor(k)
                    )
                }
                if let sfi = latest.solarFlux {
                    metricPill(
                        icon: "sun.max.fill",
                        label: "SFI",
                        value: "\(Int(sfi))",
                        color: .orange
                    )
                }
                if let aIndex = latest.solarAIndex {
                    metricPill(
                        icon: "waveform.path",
                        label: "A",
                        value: "\(aIndex)",
                        color: .purple
                    )
                }
            }
            if let latest = latestWeatherSnapshot {
                if let temp = latest.weatherTemperatureF {
                    metricPill(
                        icon: "thermometer.medium",
                        label: "",
                        value: UnitFormatter.temperatureCompact(temp),
                        color: .red
                    )
                }
            }

            Spacer()

            Text("\(snapshots.count) samples")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var sparklineChart: some View {
        Chart {
            ForEach(kIndexData, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("K-Index", point.value)
                )
                .foregroundStyle(.orange.opacity(0.8))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... max(kIndexData.map(\.value).max() ?? 5, 5))
    }

    private var timestampFooter: some View {
        Group {
            if let latest = snapshots.last {
                Text("Latest: \(latest.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max")
                .foregroundStyle(.tertiary)
            Text("No conditions data yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    private func metricPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
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
        return startOfDay.addingTimeInterval(12 * 3_600)
    }

    private func kIndexColor(_ k: Double) -> Color {
        switch k {
        case ..<2: .green
        case ..<3: .blue
        case ..<4: .yellow
        case ..<5: .orange
        default: .red
        }
    }

    private func loadRecentData() async {
        let container = modelContext.container
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        do {
            snapshots = try await dataActor.fetchSnapshots(
                from: start, to: Date(), container: container
            )
        } catch {
            snapshots = []
        }

        isLoading = false
    }
}
