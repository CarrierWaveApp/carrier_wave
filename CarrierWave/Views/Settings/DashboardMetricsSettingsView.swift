import SwiftUI

// MARK: - DashboardMetricsSettingsView

struct DashboardMetricsSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                metricPicker(selection: $metric1RawValue)
            } header: {
                Text("Primary Metric")
            } footer: {
                Text("Always shown on the dashboard card.")
            }

            Section {
                Toggle("Show second metric", isOn: showSecondMetric)
                if !metric2RawValue.isEmpty {
                    metricPicker(selection: $metric2RawValue)
                }
            } header: {
                Text("Second Metric")
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

    private var showSecondMetric: Binding<Bool> {
        Binding(
            get: { !metric2RawValue.isEmpty },
            set: { enabled in
                if enabled {
                    metric2RawValue = DashboardMetricType.activation.rawValue
                } else {
                    metric2RawValue = ""
                }
            }
        )
    }

    private func metricPicker(selection: Binding<String>) -> some View {
        Picker("Metric", selection: selection) {
            Section("Streaks") {
                ForEach(DashboardMetricType.streakCases) { type in
                    Text(type.displayName)
                        .tag(type.rawValue)
                }
            }
            Section("Counts") {
                ForEach(DashboardMetricType.countCases) { type in
                    Text(type.displayName)
                        .tag(type.rawValue)
                }
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
