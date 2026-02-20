import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SyncSourcesSection

struct SyncSourcesSection: View {
    @ObservedObject var potaAuth: POTAAuthService
    let lofiClient: LoFiClient
    let qrzClient: QRZClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let clublogClient: ClubLogClient
    @ObservedObject var iCloudMonitor: ICloudMonitor

    let qrzIsConfigured: Bool
    let qrzCallsign: String?
    let lotwIsConfigured: Bool
    let lotwUsername: String?
    let clublogIsConfigured: Bool
    let clublogCallsign: String?
    let challengeSources: [ChallengeSource]
    let tourState: TourState

    var body: some View {
        Section {
            // QRZ
            NavigationLink {
                QRZSettingsView()
            } label: {
                HStack {
                    Text("QRZ Logbook")
                    Spacer()
                    if qrzIsConfigured {
                        if let callsign = qrzCallsign {
                            Text(callsign)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            // POTA
            NavigationLink {
                POTASettingsView(potaAuth: potaAuth, tourState: tourState)
            } label: {
                HStack {
                    Text("POTA")
                    Spacer()
                    if let token = potaAuth.currentToken, !token.isExpired {
                        if let callsign = token.callsign {
                            Text(callsign)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Logged in")
                    }
                }
            }

            // LoFi
            NavigationLink {
                LoFiSettingsView(tourState: tourState)
            } label: {
                HStack {
                    Text("Ham2K LoFi")
                    Spacer()
                    if lofiClient.isConfigured {
                        if let callsign = lofiClient.getCallsign() {
                            Text(callsign)
                                .foregroundStyle(.secondary)
                        }
                        if lofiClient.isLinked {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Connected")
                        } else {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Pending connection")
                        }
                    }
                }
            }

            // HAMRS
            NavigationLink {
                HAMRSSettingsView()
            } label: {
                HStack {
                    Text("HAMRS Pro")
                    Spacer()
                    if hamrsClient.isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            // LoTW
            NavigationLink {
                LoTWSettingsView()
            } label: {
                HStack {
                    Text("LoTW")
                    Spacer()
                    if lotwIsConfigured {
                        if let username = lotwUsername {
                            Text(username)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            // Club Log
            NavigationLink {
                ClubLogSettingsView()
            } label: {
                HStack {
                    Text("Club Log")
                    Spacer()
                    if clublogIsConfigured {
                        if let callsign = clublogCallsign {
                            Text(callsign)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            // iCloud
            NavigationLink {
                CloudSyncSettingsView()
            } label: {
                HStack {
                    Text("iCloud")
                    Spacer()
                    if iCloudMonitor.iCloudContainerURL != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Available")
                    }
                }
            }

            // Activities
            NavigationLink {
                ActivitiesSettingsView()
            } label: {
                HStack {
                    Text("Activities")
                    Spacer()
                    if challengeSources.contains(where: { $0.lastFetched != nil }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            // Callsign Aliases
            NavigationLink {
                CallsignAliasesSettingsView()
            } label: {
                Text("Callsign Aliases")
            }
        } header: {
            Text("Sync Sources")
        }
    }
}
