import SwiftUI

// MARK: - AppearanceSettingsView

struct AppearanceSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            tabBarSection
            displaySection
        }
        .navigationTitle("Appearance")
    }

    // MARK: Private

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    private var tabBarSection: some View {
        Section {
            NavigationLink {
                TabConfigurationView()
            } label: {
                HStack {
                    Text(isIPad ? "Sidebar" : "Tab Bar")
                    Spacer()
                    let visibleCount = TabConfiguration.visibleTabs()
                        .filter { $0 != .more }.count
                    Text(isIPad ? "\(visibleCount) visible" : "\(visibleCount) in tab bar")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                DashboardMetricsSettingsView()
            } label: {
                Text("Dashboard Metrics")
            }
        } header: {
            Text("Navigation")
        } footer: {
            if isIPad {
                Text("Choose which tabs appear in the sidebar.")
            } else {
                Text(
                    "Choose which tabs appear in the tab bar. "
                        + "Hidden tabs are accessible from More."
                )
            }
        }
    }

    private var displaySection: some View {
        Section {
            Picker("Appearance", selection: $appearanceMode) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("Sunlight").tag("sunlight")
            }

            Picker("Units", selection: $useMetricUnits) {
                Text("Imperial (mi, \u{00B0}F, mph)").tag(false)
                Text("Metric (km, \u{00B0}C, km/h)").tag(true)
            }
        } header: {
            Text("Display")
        } footer: {
            if appearanceMode == "sunlight" {
                Text(
                    "Sunlight mode uses a bright theme with boosted contrast for "
                        + "outdoor visibility. Best for use in direct sunlight."
                )
            }
        }
    }
}
