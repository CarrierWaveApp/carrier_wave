import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - QSODetailView

struct QSODetailView: View {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static let utcDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    let qso: QSO
    let serviceConfig: ServiceConfiguration

    @State var myParkName: String?
    @State var theirParkName: String?
    @State var showEditSheet = false
    @State var refreshTask: Task<Void, Never>?

    /// One badge per service type — collapses duplicates, picks best status from each group
    var sortedPresence: [ServicePresence] {
        let filtered = qso.servicePresence
            .filter { presence in
                let configured = serviceConfig.isConfigured(presence.serviceType)
                return configured || presence.isPresent || presence.isSubmitted
            }

        let grouped = Dictionary(grouping: filtered) { $0.serviceType }
        return grouped.values
            .compactMap { records -> ServicePresence? in
                records.first(where: \.isPresent)
                    ?? records.first(where: \.isSubmitted)
                    ?? records.first
            }
            .sorted { $0.serviceType.rawValue < $1.serviceType.rawValue }
    }

    var locationLine: String? {
        let parts = [qso.qth, qso.state, qso.country].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        List {
            heroSection
            mapSection
            keyFactsSection
            statsStripSection
            stationsSection
            activityChipsSection

            Group {
                if qso.isContestQSO {
                    contestSection
                }
                if qso.satName != nil || qso.propMode != nil {
                    satelliteSection
                }
                notesQuoteSection
                clubChipsSection
                syncChipsSection
                metadataSection
            }
        }
        .navigationTitle("QSO Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showEditSheet = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EnrichedShareButton(
                    payload: EnrichedLinkPayload.from(
                        qso: qso,
                        myCall: UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
                    )
                )
            }
        }
        .sheet(isPresented: $showEditSheet) {
            QSOEditSheet(qso: qso) {
                // Refresh park names after edit
                refreshTask?.cancel()
                refreshTask = Task {
                    await refreshParkNames()
                }
            }
            .landscapeAdaptiveDetents(portrait: [.large])
        }
        .task {
            await refreshParkNames()
        }
    }

    // MARK: - Helpers

    func refreshParkNames() async {
        if let park = qso.parkReference {
            myParkName = await POTAParksCache.shared.name(for: park)
        } else {
            myParkName = nil
        }
        if let park = qso.theirParkReference {
            theirParkName = await POTAParksCache.shared.name(for: park)
        } else {
            theirParkName = nil
        }
    }
}
