import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SyncSourcesSection

struct SyncSourcesSection: View {
    var potaAuth: POTAAuthService

    let lofiClient: LoFiClient
    let qrzClient: QRZClient
    let hamrsClient: HAMRSClient
    let lotwClient: LoTWClient
    let clublogClient: ClubLogClient
    let eqslClient: EQSLClient

    let qrzIsConfigured: Bool
    let qrzCallsign: String?
    /// Set when the operator's current callsign has no QRZ key.
    var qrzLogbookMismatch: QRZLogbookCallsignMismatch?
    let lotwIsConfigured: Bool
    let lotwUsername: String?
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
                    if let mismatch = qrzLogbookMismatch {
                        Text(mismatch.logbookCallsign)
                            .foregroundStyle(.secondary)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(
                                "No QRZ logbook for \(mismatch.currentCallsign)"
                            )
                    } else if qrzIsConfigured {
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
                    if potaAuth.credentialsVerified {
                        if let callsign = potaAuth.currentToken?.callsign {
                            Text(callsign)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Verified")
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
                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // eQSL
            NavigationLink {
                EQSLSettingsView()
            } label: {
                HStack {
                    Text("eQSL")
                    ExperimentalBadge(feature: .eqsl)
                    Spacer()
                    if eqslClient.isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            // TOTA
            NavigationLink {
                TOTASettingsView()
            } label: {
                HStack {
                    Text("Tiles on the Air")
                    Spacer()
                    if TOTAClient.shared.isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }
        } header: {
            Text("Services")
        } footer: {
            Text(
                "Looking for iCloud sync or backups? They're under "
                    + "Settings > Account & Data."
            )
        }
    }
}
