import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SyncSourcesSettingsView

struct SyncSourcesSettingsView: View {
    // MARK: Internal

    @ObservedObject var potaAuth: POTAAuthService

    let tourState: TourState
    var syncService: SyncService?

    var body: some View {
        List {
            SyncSourcesSection(
                potaAuth: potaAuth,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                clublogClient: clublogClient,
                iCloudMonitor: iCloudMonitor,
                qrzIsConfigured: qrzIsConfigured,
                qrzCallsign: qrzCallsign,
                lotwIsConfigured: lotwIsConfigured,
                lotwUsername: lotwUsername,
                clublogIsConfigured: clublogIsConfigured,
                clublogCallsign: clublogCallsign,
                challengeSources: challengeSources,
                tourState: tourState
            )
        }
        .navigationTitle("Sync Sources")
        .onAppear {
            loadServiceStatus()
        }
    }

    // MARK: Private

    @Query(sort: \ChallengeSource.name) private var challengeSources: [ChallengeSource]

    @StateObject private var iCloudMonitor = ICloudMonitor()
    @State private var qrzIsConfigured = false
    @State private var qrzCallsign: String?
    @State private var lotwIsConfigured = false
    @State private var lotwUsername: String?
    @State private var clublogIsConfigured = false
    @State private var clublogCallsign: String?

    private let lofiClient = LoFiClient.appDefault()
    private let qrzClient = QRZClient()
    private let hamrsClient = HAMRSClient()
    private let lotwClient = LoTWClient()
    private let clublogClient = ClubLogClient()

    private func loadServiceStatus() {
        qrzIsConfigured = qrzClient.hasApiKey()
        qrzCallsign = qrzClient.getCallsign()

        lotwIsConfigured = lotwClient.hasCredentials()
        if lotwIsConfigured {
            if let creds = try? lotwClient.getCredentials() {
                lotwUsername = creds.username
            }
        }

        clublogIsConfigured = clublogClient.isConfigured
        clublogCallsign = clublogClient.getCallsign()
    }
}
