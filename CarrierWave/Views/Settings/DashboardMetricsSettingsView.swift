import SwiftUI

// MARK: - DashboardMetricsSettingsView

struct DashboardMetricsSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                NavigationLink {
                    MetricSelectionList(
                        selection: $metric1RawValue,
                        excludedValue: metric2RawValue
                    )
                    .navigationTitle("Primary Metric")
                } label: {
                    LabeledContent("Primary Metric", value: metric1DisplayName)
                }
            } footer: {
                Text("Always shown on the dashboard card.")
            }

            Section {
                Toggle("Show second metric", isOn: showSecondMetric)
                if !metric2RawValue.isEmpty {
                    NavigationLink {
                        MetricSelectionList(
                            selection: $metric2RawValue,
                            excludedValue: metric1RawValue
                        )
                        .navigationTitle("Second Metric")
                    } label: {
                        LabeledContent("Second Metric", value: metric2DisplayName)
                    }
                }
            } footer: {
                Text("Optionally show a second metric alongside the primary one.")
            }
        }
        .navigationTitle("Dashboard Metrics")
    }

    // MARK: Private

    @AppStorage("dashboardMetric1") private var metric1RawValue =
        DashboardMetricType.onAir.rawValue
    @AppStorage("dashboardMetric2") private var metric2RawValue =
        DashboardMetricType.activation.rawValue

    private var metric1DisplayName: String {
        DashboardMetricType(rawValue: metric1RawValue)?.displayName ?? ""
    }

    private var metric2DisplayName: String {
        DashboardMetricType(rawValue: metric2RawValue)?.displayName ?? ""
    }

    private var showSecondMetric: Binding<Bool> {
        Binding(
            get: { !metric2RawValue.isEmpty },
            set: { enabled in
                if enabled {
                    let fallback = DashboardMetricType.allCases
                        .first { $0.rawValue != metric1RawValue }
                    metric2RawValue = fallback?.rawValue
                        ?? DashboardMetricType.activation.rawValue
                } else {
                    metric2RawValue = ""
                }
            }
        )
    }
}

// MARK: - MetricSelectionList

private struct MetricSelectionList: View {
    // MARK: Internal

    @Binding var selection: String

    let excludedValue: String

    var body: some View {
        List {
            Section("Streaks") {
                ForEach(availableStreaks) { type in
                    metricRow(type: type)
                }
            }
            Section("Counts") {
                ForEach(availableCounts) { type in
                    metricRow(type: type)
                }
            }
        }
    }

    // MARK: Private

    private var availableStreaks: [DashboardMetricType] {
        DashboardMetricType.streakCases
            .filter { $0.rawValue != excludedValue }
    }

    private var availableCounts: [DashboardMetricType] {
        DashboardMetricType.countCases
            .filter { $0.rawValue != excludedValue }
    }

    private func metricRow(type: DashboardMetricType) -> some View {
        Button {
            selection = type.rawValue
        } label: {
            HStack {
                Text(type.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if selection == type.rawValue {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
