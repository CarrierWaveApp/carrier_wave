import CarrierWaveCore
import SwiftUI

// MARK: - QSODetailView

struct QSODetailView: View {
    // MARK: Internal

    let qso: QSO
    let serviceConfig: ServiceConfiguration

    var body: some View {
        List {
            headerSection
            contactSection
            locationSection

            if qso.notes?.nonEmpty != nil {
                notesSection
            }

            if !qso.servicePresence.isEmpty {
                syncSection
            }

            sourceSection
        }
        .navigationTitle("QSO Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showEditSheet = true
                }
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

    // MARK: Private

    private static let utcDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @State private var myParkName: String?
    @State private var theirParkName: String?
    @State private var showEditSheet = false
    @State private var refreshTask: Task<Void, Never>?

    private var locationLine: String? {
        let parts = [qso.qth, qso.state, qso.country].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Only show pills for configured services or services with actual data
    private var sortedPresence: [ServicePresence] {
        qso.servicePresence
            .filter { presence in
                let configured = serviceConfig.isConfigured(presence.serviceType)
                return configured || presence.isPresent || presence.isSubmitted
            }
            .sorted { $0.serviceType.rawValue < $1.serviceType.rawValue }
    }

    private func refreshParkNames() async {
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

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                Text(qso.callsign)
                    .font(.title.monospaced())
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)

                if let name = qso.name {
                    Text(name.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let locationLine {
                    Text(locationLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let licenseClass = qso.theirLicenseClass {
                    Text(licenseClass)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Contact

    private var contactSection: some View {
        Section("Contact") {
            detailRow("Date", Self.utcDateTimeFormatter.string(from: qso.timestamp) + "Z")
            detailRow("Band", qso.band)
            detailRow("Mode", qso.mode)

            if let freq = qso.frequency {
                detailRow("Frequency", FrequencyFormatter.formatWithUnit(freq))
            }

            if let rst = qso.rstSent {
                detailRow("RST Sent", rst)
            }

            if let rst = qso.rstReceived {
                detailRow("RST Received", rst)
            }

            if let power = qso.power {
                detailRow("Power", "\(power)W")
            }

            if let rig = qso.myRig {
                detailRow("Radio", rig)
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        Section("Location") {
            if let grid = qso.myGrid {
                detailRow("My Grid", grid, monospaced: true)
            }

            if let grid = qso.theirGrid {
                detailRow("Their Grid", grid, monospaced: true)
            }

            if let park = qso.parkReference {
                if let name = myParkName {
                    detailRow("My Park", "\(park) — \(name)")
                } else {
                    detailRow("My Park", park, monospaced: true)
                }
            }

            if let park = qso.theirParkReference {
                if let name = theirParkName {
                    detailRow("Their Park", "\(park) — \(name)")
                } else {
                    detailRow("Their Park", park, monospaced: true)
                }
            }

            if let sotaRef = qso.sotaRef {
                detailRow("SOTA Ref", sotaRef, monospaced: true)
            }

            if let entity = qso.dxccEntity {
                detailRow("DXCC", "\(entity.name) (#\(entity.number))")
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("Notes") {
            Text(qso.notes ?? "")
                .font(.body)
        }
    }

    // MARK: - Sync Status

    private var syncSection: some View {
        Section("Sync Status") {
            ForEach(sortedPresence) { presence in
                HStack {
                    ServicePresenceBadge(
                        presence: presence,
                        qso: qso,
                        isServiceConfigured: serviceConfig.isConfigured(presence.serviceType)
                    )

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(presenceStatusText(presence))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let date = presence.lastConfirmedAt {
                            Text(Self.dateFormatter.string(from: date) + "Z")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if qso.lotwConfirmed {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("LoTW Confirmed")
                        .font(.caption)
                    if let date = qso.lotwConfirmedDate {
                        Spacer()
                        Text(Self.dateFormatter.string(from: date) + "Z")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if qso.qrzConfirmed {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("QRZ QSL Confirmed")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Source

    private var sourceSection: some View {
        Section("Source") {
            detailRow("Import Source", importSourceLabel(qso.importSource))
            detailRow("Imported", Self.dateFormatter.string(from: qso.importedAt) + "Z")

            if let qrzId = qso.qrzLogId {
                detailRow("QRZ Log ID", qrzId, monospaced: true)
            }

            if let adif = qso.rawADIF, !adif.isEmpty {
                DisclosureGroup("Raw ADIF") {
                    Text(adif)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            if monospaced {
                Text(value)
                    .font(.body.monospaced())
            } else {
                Text(value)
            }
        }
    }

    private func presenceStatusText(_ presence: ServicePresence) -> String {
        if presence.isPresent {
            return "Present"
        } else if presence.isSubmitted {
            return "Submitted"
        } else if presence.uploadRejected {
            return "Rejected"
        } else if presence.needsUpload {
            return "Pending Upload"
        }
        return "Unknown"
    }

    private func importSourceLabel(_ source: ImportSource) -> String {
        switch source {
        case .lofi: "Ham2K LoFi"
        case .adifFile: "ADIF File"
        case .icloud: "iCloud"
        case .qrz: "QRZ"
        case .pota: "POTA"
        case .hamrs: "HAMRS"
        case .lotw: "LoTW"
        case .clublog: "Club Log"
        case .logger: "Logger"
        }
    }
}
