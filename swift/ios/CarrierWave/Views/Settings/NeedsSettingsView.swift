// Needs Settings View
//
// Settings for Smart Spot Recommendations: notification controls,
// tracking toggles, and HamAlert API key configuration (Phase 3).

import CarrierWaveData
import SwiftUI

// MARK: - NeedsSettingsView

struct NeedsSettingsView: View {
    // MARK: Lifecycle

    init() {
        // Seed `needsTrackWAS` with a country-aware default on first
        // view so operators outside the USA don't land on "all WAS
        // states missing" on first launch. The stored value, once
        // written, wins forever after.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "needsTrackWAS") == nil,
           let isUSA = UserRegionProfile.isUSAOperator
        {
            defaults.set(isUSA, forKey: "needsTrackWAS")
        }
    }

    // MARK: Internal

    var body: some View {
        Form {
            notificationsSection
            trackingSection
            hamAlertSection
        }
        .navigationTitle("Smart Spots")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @AppStorage("needsSpotNotificationsEnabled")
    private var notificationsEnabled = true

    @AppStorage("needsSpotMinPriority")
    private var minPriority = NeedPriority.high.rawValue

    @AppStorage("needsTrackDXCC") private var trackDXCC = true
    @AppStorage("needsTrackWAS") private var trackWAS = true
    @AppStorage("needsTrackPOTAHunter") private var trackPOTAHunter = true
    @AppStorage("needsTrackWWFFHunter") private var trackWWFFHunter = true
    @State private var hamAlertKey = ""
    @State private var showingKeyEntry = false

    private var hasHamAlertKey: Bool {
        (try? KeychainHelper.shared.read(for: KeychainHelper.Keys.hamAlertApiKey)) != nil
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Notify for Needed Spots", isOn: $notificationsEnabled)

            if notificationsEnabled {
                Picker("Minimum Priority", selection: $minPriority) {
                    Text("High Only").tag(NeedPriority.high.rawValue)
                    Text("Medium & High").tag(NeedPriority.medium.rawValue)
                    Text("All Priorities").tag(NeedPriority.low.rawValue)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Get notified when spots match your DXCC, WAS, or custom needs.")
        }
    }

    private var trackingSection: some View {
        Section {
            Toggle("DXCC Entities", isOn: $trackDXCC)
            Toggle("Worked All States", isOn: $trackWAS)
            Toggle("POTA Hunter Parks", isOn: $trackPOTAHunter)
            Toggle("WWFF Hunter References", isOn: $trackWWFFHunter)
        } header: {
            Text("Track Needs For")
        } footer: {
            Text(
                "Choose which award programs to track."
                    + " Disabled categories won't appear in spot badges or notifications."
            )
        }
    }

    private var hamAlertSection: some View {
        Section {
            if hasHamAlertKey {
                HStack {
                    Text("API Key")
                    Spacer()
                    Text("Configured")
                        .foregroundStyle(.green)
                }
                Button("Remove API Key", role: .destructive) {
                    removeHamAlertKey()
                }
            } else {
                Button("Configure HamAlert API Key") {
                    showingKeyEntry = true
                }
            }
            NavigationLink {
                HamAlertBackupsView()
            } label: {
                Label("Trigger Backups", systemImage: "clock.arrow.circlepath")
            }
        } header: {
            Text("HamAlert Integration")
        } footer: {
            Text("Optional. Allows exporting your needs as HamAlert triggers for alerts when you're away from the app.")
        }
        .alert("HamAlert API Key", isPresented: $showingKeyEntry) {
            TextField("API Key", text: $hamAlertKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { saveHamAlertKey() }
            Button("Cancel", role: .cancel) { hamAlertKey = "" }
        } message: {
            Text("Enter your HamAlert API key. Find it at hamalert.org under your account settings.")
        }
    }

    private func saveHamAlertKey() {
        let key = hamAlertKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return
        }
        try? KeychainHelper.shared.save(key, for: KeychainHelper.Keys.hamAlertApiKey)
        hamAlertKey = ""
    }

    private func removeHamAlertKey() {
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.hamAlertApiKey)
    }
}
