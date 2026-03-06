import Foundation

/// A spot from the WWFF Spotline service representing an active WWFF activator.
/// Decoded from `https://spots.wwff.co/spots.json`.
struct WWFFSpot: Codable, Sendable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case id
        case activator
        case reference
        case referenceInfo = "reference_info"
        case spotter
        case frequency
        case mode
        case comments
        case source
        case time
    }

    let id: Int
    let activator: String
    let reference: String // WWFF reference, e.g. "KFF-1234"
    let referenceInfo: String?
    let spotter: String
    let frequency: String // MHz as string, e.g. "14.244"
    let mode: String
    let comments: String?
    let source: String?
    let time: String // ISO-8601 timestamp

    /// Frequency in kHz for band derivation.
    nonisolated var frequencyKHz: Double? {
        guard let mhz = Double(frequency) else {
            return nil
        }
        return mhz * 1_000
    }

    /// Parsed timestamp. Spotline returns UTC ISO-8601 timestamps.
    nonisolated var parsedTimestamp: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: time) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: time) {
            return date
        }

        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: time)
    }

    /// Location name extracted from referenceInfo.
    nonisolated var locationName: String? {
        referenceInfo?.trimmingCharacters(in: .whitespaces)
    }
}
