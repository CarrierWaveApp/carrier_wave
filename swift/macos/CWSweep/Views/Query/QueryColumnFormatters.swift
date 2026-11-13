import CarrierWaveData
import Foundation

enum QueryColumnFormatters {
    // MARK: Internal

    static func format(
        value: QueryValue,
        columnName: String,
        hint: String?
    ) -> String {
        switch value {
        case .null:
            "—"
        case let .text(str):
            str
        case let .integer(int):
            formatInteger(int, columnName: columnName, hint: hint)
        case let .double(dbl):
            formatDouble(dbl, columnName: columnName, hint: hint)
        case let .blob(data):
            "<\(data.count) bytes>"
        }
    }

    // MARK: Private

    private static func formatInteger(
        _ int: Int64,
        columnName: String,
        hint: String?
    ) -> String {
        let kind = hint ?? canonicalKind(for: columnName)
        switch kind {
        case "freq_hz",
             "frequency_hz":
            return "\(Double(int) / 1_000_000.0) MHz"
        case "snr_db":
            return "\(int) dB"
        default:
            return "\(int)"
        }
    }

    private static func formatDouble(
        _ dbl: Double,
        columnName: String,
        hint: String?
    ) -> String {
        let kind = hint ?? canonicalKind(for: columnName)
        switch kind {
        case "frequency_mhz":
            return String(format: "%.4f MHz", dbl)
        case "timestamp",
             "received_at",
             "last_seen_at",
             "date":
            let date = Date(timeIntervalSince1970: dbl)
            return ISO8601DateFormatter().string(from: date)
        case "frequency":
            return String(format: "%.4f", dbl)
        default:
            return String(format: "%g", dbl)
        }
    }

    private static func canonicalKind(for columnName: String) -> String {
        switch columnName {
        case "freq_hz": "freq_hz"
        case "frequency": "frequency"
        case "snr_db": "snr_db"
        case "timestamp",
             "received_at",
             "last_seen_at",
             "date",
             "modified_at":
            "timestamp"
        default:
            columnName
        }
    }
}
