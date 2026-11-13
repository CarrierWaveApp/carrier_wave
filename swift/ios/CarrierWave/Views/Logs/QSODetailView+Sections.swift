import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Remaining Sections & Shared Helpers

extension QSODetailView {
    // MARK: - Reference predicates

    var hasReferenceFields: Bool {
        qso.parkReference != nil
            || qso.theirParkReference != nil
            || qso.sotaRef != nil
            || qso.wwffRef != nil
            || qso.aoaCode != nil
    }

    // MARK: - Contest

    var contestSection: some View {
        Section {
            if let name = qso.contestName {
                detailRow("Contest", name)
            }
            if let serial = qso.contestSerialSent {
                detailRow("Serial Sent", String(serial), monospaced: true)
            }
            if let serial = qso.contestSerialReceived {
                detailRow("Serial Received", String(serial), monospaced: true)
            }
            if let exchange = qso.contestExchangeSent {
                detailRow("Exchange Sent", exchange)
            }
            if let exchange = qso.contestExchangeReceived {
                detailRow("Exchange Received", exchange)
            }
        } header: {
            Label("Contest", systemImage: "trophy")
        }
    }

    // MARK: - Satellite

    var satelliteSection: some View {
        Section {
            if let satName = qso.satName {
                detailRow("Satellite", satName)
            }
            if let propMode = qso.propMode {
                detailRow("Propagation", propMode, monospaced: true)
            }
        } header: {
            Label("Satellite", systemImage: "satellite")
        }
    }

    // MARK: - ADIF helpers

    /// Parse rawADIF and return fields not already surfaced elsewhere in the detail view.
    /// Ensures the viewer can expose the long tail of ADIF spec fields without overwhelming
    /// the main sections.
    func unmappedADIFFields(in rawADIF: String) -> [(name: String, value: String)] {
        let fields = ADIFParser.extractFields(rawADIF)
        return fields
            .filter { !Self.mappedADIFFieldNames.contains($0.key.lowercased()) }
            .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, value: $0.value) }
    }

    /// Pretty-print an ADIF field name (e.g. "prop_mode" → "Prop Mode").
    func adifLabel(_ name: String) -> String {
        name.split(separator: "_")
            .map(\.capitalized)
            .joined(separator: " ")
    }

    /// ADIF field names already surfaced by dedicated rows in other sections.
    /// Kept conservative so anything unusual still shows up under "Other ADIF Fields".
    static let mappedADIFFieldNames: Set<String> = [
        "call", "band", "mode", "submode", "freq", "qso_date", "time_on", "time_off",
        "rst_sent", "rst_rcvd", "tx_pwr", "rx_pwr",
        "operator", "station_callsign", "my_gridsquare", "my_rig",
        "gridsquare", "name", "qth", "state", "country", "cnty",
        "dxcc", "my_dxcc",
        "pota_ref", "my_pota_ref", "sig", "sig_info", "my_sig", "my_sig_info",
        "sota_ref", "my_sota_ref", "wwff_ref", "my_wwff_ref",
        "contest_id", "srx", "stx", "srx_string", "stx_string",
        "sat_name", "prop_mode",
        "notes", "comment",
    ]

    // MARK: - Shared row + formatting helpers

    func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
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

    func presenceStatusText(_ presence: ServicePresence) -> String {
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

    func importSourceLabel(_ source: ImportSource) -> String {
        switch source {
        case .lofi: "Ham2K LoFi"
        case .adifFile: "ADIF File"
        case .icloud: "iCloud"
        case .qrz: "QRZ"
        case .pota: "POTA"
        case .hamrs: "HAMRS"
        case .lotw: "LoTW"
        case .clublog: "Club Log"
        case .eqsl: "eQSL"
        case .logger: "Logger"
        case .scanned: "Scanned"
        case .satTracker: "S.A.T."
        case .wsjtx: "WSJT-X"
        }
    }
}
