import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var config: ServerConfig

    var body: some View {
        if config.isConfigured {
            MainTabView()
        } else {
            ServerSetupView()
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.open.with.lines.needle.33percent")
                }

            AggregatorsView()
                .tabItem {
                    Label("Aggregators", systemImage: "arrow.triangle.2.circlepath")
                }

            ProgramsListView()
                .tabItem {
                    Label("Programs", systemImage: "list.bullet")
                }

            EventsListView()
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }

            ClubsListView()
                .tabItem {
                    Label("Clubs", systemImage: "person.3")
                }

            TelemetryView()
                .tabItem {
                    Label("Telemetry", systemImage: "chart.bar.xaxis.ascending")
                }

            ChallengesListView()
                .tabItem {
                    Label("Challenges", systemImage: "trophy")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
