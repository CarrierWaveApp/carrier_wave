// WWFF Agenda Item
//
// Data model for a scheduled WWFF activation from the Spotline agenda.
// Decoded from `https://spots.wwff.co/agenda.json`.

import Foundation

// MARK: - WWFFAgendaItem

/// A scheduled WWFF activation from the Spotline agenda service.
struct WWFFAgendaItem: Codable, Sendable, Identifiable {
    // MARK: Internal

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case activator
        case reference
        case referenceInfo = "reference_info"
        case startTime = "start_time"
        case endTime = "end_time"
        case frequencies
        case modes
        case comments
    }

    let id: Int
    let activator: String // Activator callsign
    let reference: String // WWFF reference, e.g. "KFF-1234"
    let referenceInfo: String? // Location name / area details
    let startTime: String // ISO-8601 timestamp for scheduled start
    let endTime: String? // ISO-8601 timestamp for scheduled end
    let frequencies: String? // Planned frequencies
    let modes: String? // Planned modes (CW, SSB, FT8, etc.)
    let comments: String?

    // MARK: - Computed

    /// Parsed start timestamp (UTC).
    nonisolated var parsedStartTime: Date? {
        Self.parseDate(startTime)
    }

    /// Parsed end timestamp (UTC).
    nonisolated var parsedEndTime: Date? {
        guard let end = endTime else {
            return nil
        }
        return Self.parseDate(end)
    }

    /// Location name extracted from referenceInfo.
    nonisolated var locationName: String? {
        referenceInfo?.trimmingCharacters(in: .whitespaces)
    }

    /// Whether this activation is currently active (between start and end times).
    nonisolated var isActive: Bool {
        guard let start = parsedStartTime else {
            return false
        }
        let now = Date()
        if let end = parsedEndTime {
            return now >= start && now <= end
        }
        // No end time — consider active for 4 hours after start
        return now >= start && now <= start.addingTimeInterval(4 * 3_600)
    }

    /// Whether this activation is upcoming (start time in the future).
    nonisolated var isUpcoming: Bool {
        guard let start = parsedStartTime else {
            return false
        }
        return start > Date()
    }

    // MARK: Private

    nonisolated private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }
}
