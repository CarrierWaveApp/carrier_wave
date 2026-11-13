// Log Submission Flavor
//
// Per-program descriptor for a log export targeted at a specific awards
// program's submission portal. Each flavor knows its own MY_SIG value,
// MY_*_REF field name, output format (ADIF or SOTA-CSV), filename
// convention, and how to extract the "my" reference from a LoggingSession.
// Used by SessionADIFExportSheet to render one share button per program
// present in an n-fer activation.

import CarrierWaveData
import UIKit

// MARK: - LogSubmissionFormat

/// Output format produced by a flavor. SOTA's database accepts CSV in its
/// own "V2" shape rather than ADIF, so the export pipeline branches here.
enum LogSubmissionFormat {
    case adif
    case sotaCSV
}

// MARK: - LogSubmissionFlavor

nonisolated enum LogSubmissionFlavor: String, CaseIterable, Identifiable {
    case pota = "POTA"
    case wwff = "WWFF"
    case sota = "SOTA"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .pota: "POTA"
        case .wwff: "WWFF"
        case .sota: "SOTA"
        }
    }

    var iconName: String {
        switch self {
        case .pota: "tree.fill"
        case .wwff: "leaf.fill"
        case .sota: "mountain.2.fill"
        }
    }

    /// MY_SIG value emitted in the ADIF for this program's submission.
    /// Unused for SOTA (CSV has no MY_SIG concept), but kept for symmetry.
    var mySig: String {
        rawValue
    }

    /// Program-specific MY_*_REF tag (ADIF flavors only).
    var myRefField: String {
        switch self {
        case .pota: "MY_POTA_REF"
        case .wwff: "MY_WWFF_REF"
        case .sota: "MY_SOTA_REF"
        }
    }

    /// Output format this flavor produces.
    var format: LogSubmissionFormat {
        switch self {
        case .pota,
             .wwff: .adif
        case .sota: .sotaCSV
        }
    }

    /// File extension used when building the share filename.
    var fileExtension: String {
        switch format {
        case .adif: "adi"
        case .sotaCSV: "csv"
        }
    }

    /// Programs the user selected for this session that we know how to flavor.
    static func availableFlavors(in session: LoggingSession) -> [LogSubmissionFlavor] {
        allCases.filter { $0.myReference(in: session) != nil }
    }

    /// "My" reference for this program from a session.
    func myReference(in session: LoggingSession) -> String? {
        switch self {
        case .pota: session.parkReference?.nonEmpty
        case .wwff: session.wwffReference?.nonEmpty
        case .sota: session.sotaReference?.nonEmpty
        }
    }

    /// Per-program filename convention.
    /// POTA / SOTA use the underscored `<call>_<ref>_YYYY-MM-DD.<ext>` form;
    /// WWFF Global Rules require `<CALL> @ <REF> YYYYMMDD.adi`.
    func filename(activatorCallsign: String, reference: String, date: Date) -> String {
        switch self {
        case .pota,
             .sota:
            underscoredFilename(
                activatorCallsign: activatorCallsign,
                reference: reference,
                date: date,
                fileExtension: fileExtension
            )
        case .wwff:
            WWFFRepresentativeDirectory.logFilename(
                reference: reference,
                callsign: activatorCallsign,
                dateYYYYMMDD: Self.compactUTCDate(date)
            )
        }
    }

    // MARK: Private

    private static func compactUTCDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func underscoredFilename(
        activatorCallsign: String,
        reference: String,
        date: Date,
        fileExtension: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = formatter.string(from: date)
        let safeCall = activatorCallsign
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let safeRef = reference
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        return "\(safeCall)_\(safeRef)_\(dateStr).\(fileExtension)"
    }
}
