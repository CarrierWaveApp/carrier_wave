import CarrierWaveData
import Foundation

// MARK: - PendingUploadExporter

/// Generates export content (CSV, Markdown, ADIF) from pending upload items.
enum PendingUploadExporter {
    // MARK: Internal

    /// Export as markdown table (for clipboard).
    static func markdown(
        items: [PendingUploadItem],
        serviceFilter: ServiceType?
    ) -> String {
        var lines = buildHeader(items: items, serviceFilter: serviceFilter, format: "Markdown")
        lines.append("")
        lines.append("| Callsign | Date (UTC) | Band | Mode | Services | Reason | Detail |")
        lines.append("|----------|------------|------|------|----------|--------|--------|")
        for item in items {
            let date = dateFormatter.string(from: item.timestamp)
            let services = item.services.map(\.displayName).joined(separator: ", ")
            let detail = item.detail.isEmpty ? "-" : item.detail
            lines.append("| \(item.callsign) | \(date) | \(item.band) | \(item.mode)"
                + " | \(services) | \(item.reason.title) | \(detail) |")
        }
        return lines.joined(separator: "\n")
    }

    /// Export as CSV file content.
    static func csv(
        items: [PendingUploadItem],
        serviceFilter: ServiceType?
    ) -> String {
        var lines = buildHeader(items: items, serviceFilter: serviceFilter, format: "CSV")
        lines.append("")
        lines.append("Callsign,Date (UTC),Band,Mode,Services,Reason,Detail")
        for item in items {
            let date = dateFormatter.string(from: item.timestamp)
            let services = item.services.map(\.displayName).joined(separator: "; ")
            let detail = csvEscape(item.detail)
            lines.append(
                "\(item.callsign),\(date),\(item.band),\(item.mode),"
                    + "\(csvEscape(services)),\(item.reason.title),\(detail)"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Export as ADIF (just the pending QSOs for manual upload).
    static func adif(
        items: [PendingUploadItem],
        serviceFilter: ServiceType?
    ) -> String {
        var lines: [String] = []

        let filterDesc = serviceFilter?.displayName ?? "All Services"
        lines.append("Carrier Wave - Pending Uploads Export (\(filterDesc))")
        lines.append("")
        lines.append(adifField("ADIF_VER", "3.1.7"))
        lines.append(adifField("PROGRAMID", "CarrierWave"))
        let ts = timestampFormatter.string(from: Date())
        lines.append(adifField("CREATED_TIMESTAMP", ts))
        lines.append("<EOH>")
        lines.append("")

        for item in items {
            lines.append(buildADIFRecord(item))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static let timestampFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd HHmmss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static let adifDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static let adifTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HHmmss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static func buildHeader(
        items: [PendingUploadItem],
        serviceFilter: ServiceType?,
        format: String
    ) -> [String] {
        let callsign = CallsignAliasService.shared.getCurrentCallsign() ?? "unknown"
        let filterDesc = serviceFilter?.displayName ?? "All Services"
        let ts = dateFormatter.string(from: Date())
        return [
            "# Carrier Wave - Pending Uploads Export",
            "# Format: \(format)",
            "# Generated: \(ts) UTC",
            "# Filter: \(filterDesc)",
            "# Primary callsign: \(callsign)",
            "# Total: \(items.count) QSOs",
        ]
    }

    private static func buildADIFRecord(_ item: PendingUploadItem) -> String {
        var fields: [String] = []
        fields.append(adifField("CALL", item.callsign))
        if !item.band.isEmpty {
            fields.append(adifField("BAND", item.band))
        }
        fields.append(adifField("MODE", item.mode))
        if let freq = item.frequency {
            fields.append(adifField("FREQ", String(format: "%.6f", freq)))
        }
        fields.append(adifField("QSO_DATE", adifDateFormatter.string(from: item.timestamp)))
        fields.append(adifField("TIME_ON", adifTimeFormatter.string(from: item.timestamp)))
        if !item.myCallsign.isEmpty {
            fields.append(adifField("STATION_CALLSIGN", item.myCallsign))
        }
        if let park = item.parkReference, !park.isEmpty {
            fields.append(adifField("MY_SIG", "POTA"))
            fields.append(adifField("MY_SIG_INFO", park))
        }
        // Add reason as comment for reference
        let comment = "Pending: \(item.reason.title)"
            + (item.detail.isEmpty ? "" : " - \(item.detail)")
        fields.append(adifField("COMMENT", comment))
        return fields.joined() + "<EOR>"
    }

    private static func adifField(_ name: String, _ value: String) -> String {
        "<\(name.uppercased()):\(value.utf8.count)>\(value)"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
