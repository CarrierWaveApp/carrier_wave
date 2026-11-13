import Foundation

// MARK: - POTASpotComment

public struct POTASpotComment: Codable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        spotId: Int64,
        spotter: String,
        comments: String?,
        spotTime: String,
        source: String?
    ) {
        self.spotId = spotId
        self.spotter = spotter
        self.comments = comments
        self.spotTime = spotTime
        self.source = source
    }

    // MARK: Public

    public let spotId: Int64
    public let spotter: String
    public let comments: String?
    public let spotTime: String
    public let source: String?

    nonisolated public var id: Int64 {
        spotId
    }

    /// Parse spot time to Date
    /// POTA API returns timestamps without timezone suffix — these are UTC.
    nonisolated public var timestamp: Date? {
        let formatter = ISO8601DateFormatter()

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: spotTime) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: spotTime) {
            return date
        }

        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        if let date = formatter.date(from: spotTime) {
            return date
        }

        formatter.formatOptions = [
            .withFullDate, .withTime, .withColonSeparatorInTime, .withFractionalSeconds,
        ]
        return formatter.date(from: spotTime)
    }

    nonisolated public var timeAgo: String {
        guard let timestamp else {
            return ""
        }
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3_600))h ago"
        }
    }

    nonisolated public var isAutomatedSpot: Bool {
        guard let source = source?.uppercased() else {
            return false
        }
        return source == "RBN"
    }

    nonisolated public var isHumanSpot: Bool {
        !isAutomatedSpot
    }

    /// Extract WPM from RBN comment text (e.g., "14 dB 22 WPM CQ")
    nonisolated public var wpm: Int? {
        guard let comments else {
            return nil
        }
        let pattern = #/(\d+)\s*WPM/#
        guard let match = comments.firstMatch(of: pattern) else {
            return nil
        }
        return Int(match.1)
    }
}

// MARK: - RoveStop

public struct RoveStop: Codable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        parkReference: String,
        startedAt: Date,
        endedAt: Date? = nil,
        myGrid: String? = nil,
        qsoCount: Int = 0,
        notes: String? = nil
    ) {
        self.id = id
        self.parkReference = parkReference
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.myGrid = myGrid
        self.qsoCount = qsoCount
        self.notes = notes
    }

    // MARK: Public

    public var id: UUID = .init()
    public var parkReference: String
    public var startedAt: Date
    public var endedAt: Date?
    public var myGrid: String?
    public var qsoCount: Int = 0
    public var notes: String?

    public var isActive: Bool {
        endedAt == nil
    }

    public var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    public var formattedDuration: String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
