import SwiftUI

// MARK: - Help & Support / About sections

extension SettingsMainView {
    var helpSection: some View {
        Section {
            Button {
                showingBugReport = true
            } label: {
                Text("Report a Bug")
            }

            Button {
                showingSendDiagnostics = true
            } label: {
                Text("Send Diagnostics")
            }
            .accessibilityHint(
                "Packages app logs and sync history into a "
                    + "file you can share with support"
            )

            Link(destination: URL(string: "https://discord.gg/PqubUxWW62")!) {
                Text("Join Discord")
            }

            Link(destination: URL(string: "https://discord.gg/ksNb2jAeTR")!) {
                Text("Request a Feature")
            }

            Button {
                tourState.resetForTesting()
                showIntroTour = true
            } label: {
                Text("Show App Tour")
            }
        } header: {
            Text("Help & Support")
        }
    }

    var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersionString)
                    .foregroundStyle(.secondary)
            }

            Button {
                showWhatsNew = true
            } label: {
                Text("What's New")
            }

            NavigationLink {
                AttributionsView()
            } label: {
                Text("Attributions")
            }

            Link(destination: URL(string: "https://carrierwave.app/privacy.html")!) {
                Text("Privacy Policy")
            }
        } header: {
            Text("About")
        }
    }

    /// Read the marketing version from the bundle so it stays in sync with
    /// `MARKETING_VERSION` in `CarrierWave.xcodeproj` without manual edits.
    var appVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
