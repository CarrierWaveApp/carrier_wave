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
                    Label("QRZ Logbook", systemImage: "globe")
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
                    Label("POTA", systemImage: "leaf")
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
                    Label("Ham2K LoFi", systemImage: "antenna.radiowaves.left.and.right")
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
                    Label("HAMRS Pro", systemImage: "rectangle.stack")
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
                    Label("LoTW", systemImage: "envelope.badge.shield.half.filled")
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
                    Label("Club Log", systemImage: "chart.bar.xaxis")
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
                ICloudSettingsView()
            } label: {
                HStack {
                    Label("iCloud Folder", systemImage: "icloud")
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
                    Label("Activities", systemImage: "flag.2.crossed")
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
                Label("Callsign Aliases", systemImage: "person.text.rectangle")
            }
        } header: {
            Text("Sync Sources")
        }
    }
}
