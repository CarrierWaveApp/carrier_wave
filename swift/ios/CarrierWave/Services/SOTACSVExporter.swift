// SOTA CSV Exporter
//
// Generates SOTA database "V2" CSV rows from QSO snapshots for an activator
// submission. Format per https://www.sotadata.org.uk:
//
//   V2,<owncall>,<owncall>,<DD/MM/YY>,<HHMM>,<freq-or-band>,<mode>,
//      <theircall>,<theirsummit-or-blank>,<comment>
//
// The activator's own summit is implied by the upload context (the user
// selects the summit on the SOTA submission page) so it does not appear in
// each row. Summit-to-summit contacts put the worked station's summit in
// the `theirsummit` column.

import CarrierWaveData
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - ShareableSOTACSV

/// Transferable wrapper for sharing a SOTA submission CSV file. Mirrors
/// `ShareableADIF` but registers a `.commaSeparatedText` content type so
/// the share sheet offers spreadsheet apps + the SOTA web upload page.
struct ShareableSOTACSV: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(item.filename)
            try item.content.write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
            return SentTransferredFile(fileURL)
        }
    }

    let content: String
    let filename: String
}

// MARK: - SOTACSVExporter

actor SOTACSVExporter {
    // MARK: Internal

    /// Build a V2 CSV body for the given QSOs. Metadata pseudo-modes
    /// (WEATHER / SOLAR / NOTE) are filtered out; SOTA only wants real QSOs.
    func generate(
        snapshots: [QSOExportSnapshot],
        activatorCallsign: String
    ) async -> String {
        let safeCall = csvField(activatorCallsign.uppercased())
        var lines: [String] = []
        lines.reserveCapacity(snapshots.count)
        let sorted = snapshots.sorted { $0.timestamp < $1.timestamp }
        for snapshot in sorted where !QSOMode.isMetadata(snapshot.mode) {
            lines.append(buildRow(snapshot: snapshot, ownCall: safeCall))
            await Task.yield()
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Standard amateur band labels → SOTA "<NN>MHz" form.
    private static let bandToMHz: [String: String] = [
        "160m": "1.8MHz",
        "80m": "3.5MHz",
        "60m": "5MHz",
        "40m": "7MHz",
        "30m": "10MHz",
        "20m": "14MHz",
        "17m": "18MHz",
        "15m": "21MHz",
        "12m": "24MHz",
        "10m": "28MHz",
        "6m": "50MHz",
        "4m": "70MHz",
        "2m": "144MHz",
        "1.25m": "222MHz",
        "70cm": "432MHz",
        "33cm": "902MHz",
        "23cm": "1.2GHz",
        "13cm": "2.3GHz",
    ]

    private func buildRow(snapshot: QSOExportSnapshot, ownCall: String) -> String {
        let date = Self.dateFormatter.string(from: snapshot.timestamp)
        let time = Self.timeFormatter.string(from: snapshot.timestamp)
        let freqOrBand = freqOrBand(snapshot: snapshot)
        let mode = sotaMode(adifMode: snapshot.mode)
        let theirCall = csvField(snapshot.callsign.uppercased())
        let theirSummit = csvField(snapshot.sotaRef?.uppercased() ?? "")
        let comment = csvField(snapshot.notes ?? "")
        return [
            "V2", ownCall, ownCall, date, time,
            freqOrBand, mode, theirCall, theirSummit, comment,
        ].joined(separator: ",")
    }

    private func freqOrBand(snapshot: QSOExportSnapshot) -> String {
        if let freq = snapshot.frequency {
            return String(format: "%.3f", freq)
        }
        return Self.bandToMHz[snapshot.band.lowercased()] ?? snapshot.band
    }

    /// Map ADIF mode strings to SOTA's accepted set. SSB/USB/LSB collapse to
    /// SSB; digital modes collapse to DATA; CW/FM/AM pass through.
    private func sotaMode(adifMode: String) -> String {
        switch adifMode.uppercased() {
        case "CW": "CW"
        case "FM": "FM"
        case "AM": "AM"
        case "SSB",
             "USB",
             "LSB": "SSB"
        default: "DATA"
        }
    }

    /// Quote a CSV field per RFC 4180: wrap in `"` and double any interior `"`
    /// when the field contains a comma, quote, or newline.
    private func csvField(_ value: String) -> String {
        let needsQuoting =
            value.contains(",") || value.contains("\"") || value.contains("\n")
                || value.contains("\r")
        if !needsQuoting {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
