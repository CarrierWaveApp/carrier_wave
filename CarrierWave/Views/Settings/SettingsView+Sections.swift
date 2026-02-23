import SwiftData
import SwiftUI

// MARK: - Sections

extension SettingsMainView {
    var profileSection: some View {
        Section {
            NavigationLink {
                AboutMeView {
                    showOnboarding = true
                }
            } label: {
                HStack {
                    if let profile = userProfile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.callsign)
                                .font(.headline)
                                .monospaced()
                            if let name = profile.fullName {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let licenseClass = profile.licenseClass {
                            Text(licenseClass.abbreviation)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Color.accentColor.opacity(0.2)
                                )
                                .clipShape(Capsule())
                        }
                    } else {
                        Text("Set Up Profile")
                    }
                }
            }
        } header: {
            Text("My Profile")
        }
    }

    var generalSection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Text("Appearance")
            }

            NavigationLink {
                LoggerDetailSettingsView()
            } label: {
                Text("Logger")
            }

            NavigationLink {
                POTAActivationSettingsView()
            } label: {
                Text("POTA Activations")
            }

            NavigationLink {
                SyncSourcesSettingsView(
                    potaAuth: potaAuth,
                    tourState: tourState,
                    syncService: syncService
                )
            } label: {
                Text("Sync Sources")
            }

            NavigationLink {
                DataToolsSettingsView()
            } label: {
                Text("Data & Tools")
            }
        }
    }

    var developerSection: some View {
        Section {
            Toggle("Debug Mode", isOn: $debugMode)

            if debugMode {
                Toggle("Read-Only Mode", isOn: $readOnlyMode)
                Toggle(
                    "Bypass POTA Maintenance",
                    isOn: $bypassPOTAMaintenance
                )

                NavigationLink {
                    SyncDebugView(potaAuth: potaAuth)
                } label: {
                    Text("Sync Debug Log")
                }

                NavigationLink {
                    AllHiddenQSOsView()
                } label: {
                    Text("Hidden QSOs")
                }

                HStack {
                    Text("CW-SWL Server")
                    TextField(
                        "http://host:3000",
                        text: $cwswlServerURL
                    )
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
                }

                Button(role: .destructive) {
                    showingClearAllConfirmation = true
                } label: {
                    if isClearingQSOs {
                        HStack {
                            ProgressView()
                            Text("Clearing...")
                        }
                    } else {
                        Text("Clear All QSOs")
                    }
                }
                .disabled(isClearingQSOs)
            }
        } header: {
            Text("Developer")
        } footer: {
            if debugMode, bypassPOTAMaintenance {
                Text(
                    "POTA maintenance window bypass enabled. "
                        + "Uploads allowed 24/7."
                )
            } else if debugMode, readOnlyMode {
                Text(
                    "Read-only mode: uploads disabled. "
                        + "Downloads and local changes still work."
                )
            } else {
                Text(
                    "Shows individual sync buttons on service cards "
                        + "and debug tools"
                )
            }
        }
    }

    var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.43.1")
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://discord.gg/PqubUxWW62")!) {
                Text("Join Discord")
            }

            Button {
                showingBugReport = true
            } label: {
                Text("Report a Bug")
            }

            Button {
                tourState.resetForTesting()
                showIntroTour = true
            } label: {
                Text("Show App Tour")
            }

            Link(destination: URL(string: "https://discord.gg/ksNb2jAeTR")!) {
                Text("Request a Feature")
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

    func clearAllQSOs() async {
        isClearingQSOs = true
        defer { isClearingQSOs = false }

        do {
            try modelContext.delete(model: QSO.self)
            try modelContext.save()
            lofiClient.resetSyncTimestamp()
            NotificationCenter.default.post(
                name: .didClearQSOs, object: nil
            )
        } catch {
            errorMessage =
                "Failed to clear QSOs: \(error.localizedDescription)"
            showingError = true
        }
    }
}
