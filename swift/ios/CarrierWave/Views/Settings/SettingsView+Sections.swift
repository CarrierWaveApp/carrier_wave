import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Sections

extension SettingsMainView {
    var profileSection: some View {
        Section {
            if let pending = pendingCallsignChange {
                NavigationLink {
                    CallsignChangeGuideView(
                        syncService: syncService,
                        tourState: tourState
                    )
                } label: {
                    CallsignChangePendingRow(pending: pending)
                }
            }

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

            OperatorRolePickerRow()

            NavigationLink {
                CallsignAliasesSettingsView()
            } label: {
                Text("Callsign Aliases")
            }
        } header: {
            Text("My Profile")
        }
    }

    /// Your data: device/cloud sync and local snapshots.
    var accountDataSection: some View {
        Section {
            if ExperimentalFeature.isEnabled(.syncServer) {
                NavigationLink {
                    SyncPassphraseView()
                } label: {
                    HStack {
                        Text("Carrier Wave Sync")
                        Spacer()
                        ExperimentalBadge(feature: .syncServer)
                    }
                }
            }

            NavigationLink {
                CloudSyncSettingsView()
            } label: {
                HStack {
                    Text("iCloud Sync")
                    ExperimentalBadge(feature: .icloudSync)
                    Spacer()
                    if CloudSyncService.shared.isEnabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Enabled")
                    }
                }
            }

            NavigationLink {
                BackupSettingsView()
            } label: {
                Text("Backups")
            }
        } header: {
            Text("Account & Data")
        } footer: {
            Text("Sync keeps your logbook on all your devices. Backups protect against data loss.")
        }
    }

    /// Third-party logbook sync and the community server.
    var servicesSection: some View {
        Section {
            NavigationLink {
                SyncSourcesSettingsView(
                    potaAuth: potaAuth,
                    tourState: tourState,
                    syncService: syncService
                )
            } label: {
                Text("Logbook Services")
            }

            NavigationLink {
                ActivitiesSettingsView()
            } label: {
                Text("Community")
            }

            NavigationLink {
                AMTSettingsView()
            } label: {
                HStack {
                    Text("Another Morse Trainer")
                    Spacer()
                    if AMTService.shared.isSignedIn {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            if ExperimentalFeature.isEnabled(.wsjtx) {
                WsjtxServicesRow()
            }
        } header: {
            Text("Services")
        } footer: {
            Text(
                "Logbook Services syncs QSOs with QRZ, POTA, LoTW, and others. "
                    + "Community covers friends, clubs, and the activity feed. "
                    + "Another Morse Trainer shows your Morse practice streak."
            )
        }
    }

    /// One row per app surface, all at the same depth.
    var featuresSection: some View {
        Section {
            NavigationLink {
                LoggerDetailSettingsView()
            } label: {
                Text("Logger")
            }

            NavigationLink {
                ActivityLogSettingsView()
            } label: {
                Text("Hunter Log")
            }

            NavigationLink {
                POTAActivationSettingsView()
            } label: {
                Text("POTA Activations")
            }

            NavigationLink {
                OnAirSettingsView()
            } label: {
                Text("On Air Now")
            }

            NavigationLink {
                HuntSettingsView()
            } label: {
                Text("Hunt & P2P")
            }

            NavigationLink {
                DashboardMetricsSettingsView()
            } label: {
                Text("Dashboard Metrics")
            }

            NavigationLink {
                ContestCalendarSettingsView()
            } label: {
                Text("Contest Calendar")
            }
        } header: {
            Text("Features")
        }
    }

    var hardwareSection: some View {
        Section {
            NavigationLink {
                RadioSettingsView(radioService: RadioService.shared)
            } label: {
                HStack {
                    Text("Radio")
                    ExperimentalBadge(feature: .radioControl)
                    Spacer()
                    if RadioService.shared.isConnected {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    } else if RadioService.shared.isConfigured {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                    }
                }
            }

            NavigationLink {
                EquipmentBrowserView()
            } label: {
                Text("My Equipment")
            }
        } header: {
            Text("Hardware")
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
                DataToolsSettingsView()
            } label: {
                Text("Data & Tools")
            }
        } header: {
            Text("General")
        }
    }

    var developerSection: some View {
        Section {
            NavigationLink {
                ExperimentsView()
            } label: {
                Text("Experiments")
            }

            Toggle("Debug Mode", isOn: $debugMode)

            if debugMode {
                Toggle(
                    "Bypass POTA Maintenance",
                    isOn: $bypassPOTAMaintenance
                )
                Toggle(
                    "Performance Profiler",
                    isOn: $startupProfilerEnabled
                )

                NavigationLink {
                    StartupProfileView()
                } label: {
                    Text("Profile Trace")
                }

                NavigationLink {
                    SyncDebugView(potaAuth: potaAuth)
                } label: {
                    Text("Sync Debug Log")
                }

                NavigationLink {
                    SpotlightDebugView()
                } label: {
                    Text("Spotlight Debug")
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

                HStack {
                    Text("Activities Server")
                    TextField(
                        "https://activities.carrierwave.app",
                        text: $activitiesServerURL
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
            Text("Advanced")
        } footer: {
            if debugMode, bypassPOTAMaintenance {
                Text(
                    "POTA maintenance window bypass enabled. "
                        + "Uploads allowed 24/7."
                )
            } else {
                Text(
                    "Shows individual sync buttons on service cards "
                        + "and debug tools"
                )
            }
        }
    }

    func clearAllQSOs() async {
        isClearingQSOs = true
        defer { isClearingQSOs = false }

        do {
            try modelContext.delete(model: QSO.self)
            try modelContext.save()
            // A bulk `delete(model:)` fires no per-object change notification, so the
            // cw-store mirror never sees it. Prune the follower to match the now-empty
            // SwiftData store directly (no-op when the experiment is off / store empty).
            if ExperimentalFeature.isEnabled(.rustStoreQSO) {
                pruneCwStoreFollower(container: modelContext.container)
            }
            lofiClient.resetSyncTimestamp()
            NotificationCenter.default.post(
                name: .didClearQSOs, object: nil
            )
            // CAR-264: clearing the local QSO store leaves the CKSyncEngine
            // change token in place, which makes a subsequent fetch a no-op
            // (the cloud-side journals are all "already applied") and the
            // cloud copy never repopulates. Force the sync subsystem to
            // re-bootstrap so the user gets their logbook back from iCloud
            // the same way a fresh install would.
            await CloudSyncService.shared.resetForLocalWipe()
        } catch {
            errorMessage =
                "Failed to clear QSOs: \(error.localizedDescription)"
            showingError = true
        }
    }

    /// Fire-and-forget cw-store orphan prune after a mirror-blind bulk delete.
    /// Drains in-flight follower writes first, then reconciles on a background context.
    func pruneCwStoreFollower(container: ModelContainer) {
        Task.detached(priority: .utility) {
            let mirror = await MainActor.run { CwStoreMirrorRegistry.current }
            await mirror?.drain()
            do {
                let store = try await CwStoreProvider.shared.store()
                let context = ModelContext(container)
                _ = try CwStoreReconciler(store: store).reconcileAll(in: context)
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    CwStoreWriteLog.shared.record("cw-store prune after clear failed: \(message)")
                }
            }
        }
    }
}
