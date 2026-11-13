// WWFF Agenda Item
//
// Data model for a scheduled WWFF activation from the Spotline agenda.
// Parsed from the HTML table at `https://spots.wwff.co/agenda`.

import Foundation

// MARK: - WWFFAgendaItem

/// A scheduled WWFF activation from the Spotline agenda service.
public struct WWFFAgendaItem: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: Int,
        activator: String,
        reference: String,
        referenceInfo: String?,
        startTime: String,
        endTime: String?,
        frequencies: String?,
        modes: String?,
        comments: String?
    ) {
        self.id = id
        self.activator = activator
        self.reference = reference
        self.referenceInfo = referenceInfo
        self.startTime = startTime
        self.endTime = endTime
        self.frequencies = frequencies
        self.modes = modes
        self.comments = comments
    }

    // MARK: Public

    public let id: Int
    public let activator: String // Activator callsign
    public let reference: String // WWFF reference, e.g. "KFF-1234"
    public let referenceInfo: String? // Location name / area details
    public let startTime: String // ISO-8601 timestamp for scheduled start
    public let endTime: String? // ISO-8601 timestamp for scheduled end
    public let frequencies: String? // Planned frequencies
    public let modes: String? // Planned modes (CW, SSB, FT8, etc.)
    public let comments: String?

    // MARK: - Computed

    /// Parsed start timestamp (UTC).
    nonisolated public var parsedStartTime: Date? {
        Self.parseDate(startTime)
    }

    /// Parsed end timestamp (UTC).
    nonisolated public var parsedEndTime: Date? {
        guard let end = endTime else {
            return nil
        }
        return Self.parseDate(end)
    }

    /// Location name extracted from referenceInfo.
    nonisolated public var locationName: String? {
        referenceInfo?.trimmingCharacters(in: .whitespaces)
    }

    /// Whether this activation is currently active (between start and end times).
    nonisolated public var isActive: Bool {
        guard let start = parsedStartTime else {
            return false
        }
        let now = Date()
        if let end = parsedEndTime {
            return now >= start && now <= end
        }
        // No end time -- consider active for 4 hours after start
        return now >= start && now <= start.addingTimeInterval(4 * 3_600)
    }

    /// Whether this activation is upcoming (start time in the future).
    nonisolated public var isUpcoming: Bool {
        guard let start = parsedStartTime else {
            return false
        }
        return start > Date()
    }

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
