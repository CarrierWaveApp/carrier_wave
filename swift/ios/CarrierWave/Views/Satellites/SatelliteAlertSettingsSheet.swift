import SwiftUI
import UIKit
import UserNotifications

// MARK: - SatelliteAlertSettingsSheet

/// Pass-alert configuration (bell button on the satellites tab): the master
/// toggle, lead time, the marginal-pass opt-in, notification-permission
/// state, and the favorites list the alerts are computed from.
struct SatelliteAlertSettingsSheet: View {
    // MARK: Internal

    /// Resolves a NORAD ID to a display name (from the tracker's catalog).
    let satelliteName: (Int) -> String?

    var body: some View {
        NavigationStack {
            Form {
                alertsSection
                if alertsEnabled {
                    optionsSection
                }
                favoritesSection
            }
            .navigationTitle("Pass Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await refreshAuthorizationStatus()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SatellitePassAlertScheduler.enabledKey) private var alertsEnabled = false
    @AppStorage(SatellitePassAlertScheduler.leadMinutesKey) private var leadMinutes = 15
    @AppStorage(SatellitePassAlertScheduler.includeMarginalKey) private var includeMarginal = false
    @State private var authorizationDenied = false

    private var favorites: FavoriteSatellitesStore {
        .shared
    }

    private var scheduler: SatellitePassAlertScheduler {
        .shared
    }

    private var alertsSection: some View {
        Section {
            Toggle("Pass alerts for favorites", isOn: $alertsEnabled)
                .onChange(of: alertsEnabled) { _, enabled in
                    if enabled {
                        Task {
                            _ = await SatellitePassAlertScheduler.ensureAuthorization()
                            await refreshAuthorizationStatus()
                            scheduler.reschedule(trigger: "alerts-enabled")
                        }
                    } else {
                        scheduler.reschedule(trigger: "alerts-disabled")
                    }
                }
            if authorizationDenied {
                Label {
                    Text("Notifications are denied — allow them in Settings")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .font(.caption)
                }
            }
        } footer: {
            Text(
                "Notifies before each pass of a favorited satellite that peaks at "
                    + "≥\(Int(SatelliteWorkability.recommendedPassElevationDeg))° "
                    + "(the handheld-antenna recommendation)."
            )
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            Picker("Lead time", selection: $leadMinutes) {
                ForEach([10, 15, 30], id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .onChange(of: leadMinutes) {
                scheduler.reschedule(trigger: "lead-time")
            }
            Toggle("Include marginal passes (10–20°)", isOn: $includeMarginal)
                .onChange(of: includeMarginal) {
                    scheduler.reschedule(trigger: "marginal-toggle")
                }
            LabeledContent("Scheduled alerts", value: "\(scheduler.pendingAlertCount)")
        }
    }

    private var favoritesSection: some View {
        Section {
            if favorites.noradIDs.isEmpty {
                Text("No favorites yet — star a satellite from its info card or the search list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(favorites.noradIDs.sorted(), id: \.self) { noradID in
                    HStack {
                        Text(satelliteName(noradID) ?? "NORAD \(String(noradID))")
                            .font(.subheadline.monospaced())
                        Spacer()
                        Button {
                            favorites.toggle(noradID)
                        } label: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove from favorites")
                    }
                }
            }
        } header: {
            Text("Favorites")
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationDenied = settings.authorizationStatus == .denied
    }
}
