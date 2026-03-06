import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - ActivationType

public enum ActivationType: String, Codable, CaseIterable {
    case casual
    case pota
    case sota
    case aoa
    case wwff

    // MARK: Public

    public var displayName: String {
        switch self {
        case .casual: "Casual"
        case .pota: "POTA"
        case .sota: "SOTA"
        case .aoa: "AoA"
        case .wwff: "WWFF"
        }
    }

    public var icon: String {
        switch self {
        case .casual: "radio"
        case .pota: "tree"
        case .sota: "mountain.2"
        case .aoa: "eye"
        case .wwff: "leaf.fill"
        }
    }

    public static func from(programs: Set<String>) -> ActivationType {
        if programs.contains("pota") {
            return .pota
        }
        if programs.contains("wwff") {
            return .wwff
        }
        if programs.contains("sota") {
            return .sota
        }
        if programs.contains("aoa") {
            return .aoa
        }
        return .casual
    }
}

// MARK: - LoggingSessionStatus

public enum LoggingSessionStatus: String, Codable {
    case active
    case paused
    case completed
}

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

// MARK: - LoggingSession

@Model
nonisolated public final class LoggingSession {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        myCallsign: String,
        startedAt: Date = Date(),
        frequency: Double? = nil,
        mode: String = "CW",
        programs: Set<String> = [],
        activationType: ActivationType = .casual,
        parkReference: String? = nil,
        sotaReference: String? = nil,
        missionReference: String? = nil,
        wwffReference: String? = nil,
        myGrid: String? = nil,
        notes: String? = nil,
        power: Int? = nil,
        myRig: String? = nil,
        myAntenna: String? = nil,
        myKey: String? = nil,
        myMic: String? = nil,
        extraEquipment: String? = nil,
        attendees: String? = nil,
        contestId: String? = nil,
        contestCategory: String? = nil,
        contestPower: String? = nil,
        contestBands: String? = nil,
        contestOperator: String? = nil
    ) {
        self.id = id
        self.myCallsign = myCallsign
        self.startedAt = startedAt
        self.frequency = frequency
        self.mode = mode
        activationTypeRawValue = activationType.rawValue
        self.parkReference = parkReference
        self.sotaReference = sotaReference
        self.missionReference = missionReference
        self.wwffReference = wwffReference
        self.myGrid = myGrid
        self.notes = notes
        self.power = power
        self.myRig = myRig
        self.myAntenna = myAntenna
        self.myKey = myKey
        self.myMic = myMic
        self.extraEquipment = extraEquipment
        self.attendees = attendees

        self.contestId = contestId
        self.contestCategory = contestCategory
        self.contestPower = contestPower
        self.contestBands = contestBands
        self.contestOperator = contestOperator

        if !programs.isEmpty {
            self.programs = programs
        } else if activationType != .casual {
            self.programs = [activationType.rawValue]
        }
    }

    // MARK: Public

    public var id = UUID()
    public var myCallsign = ""
    public var startedAt = Date()
    public var endedAt: Date?
    public var frequency: Double?
    public var mode = "CW"
    public var activationTypeRawValue: String = ActivationType.casual.rawValue
    public var programsRawValue: String = ""
    public var statusRawValue: String = LoggingSessionStatus.active.rawValue
    public var parkReference: String?
    public var sotaReference: String?
    public var missionReference: String?
    public var wwffReference: String?
    public var myGrid: String?
    public var power: Int?
    public var myRig: String?
    public var notes: String?
    public var customTitle: String?
    public var qsoCount: Int = 0
    public var spotCommentsData: Data?
    public var isRove: Bool = false
    public var roveStopsData: Data?
    public var myAntenna: String?
    public var myKey: String?
    public var myMic: String?
    public var extraEquipment: String?
    public var attendees: String?
    public var photoFilenames: [String] = []

    // Conditions
    public var solarKIndex: Double?
    public var solarFlux: Double?
    public var solarSunspots: Int?
    public var solarPropagationRating: String?
    public var solarAIndex: Int?
    public var solarBandConditions: String?
    public var solarTimestamp: Date?
    public var solarConditions: String?
    public var weatherTemperatureF: Double?
    public var weatherTemperatureC: Double?
    public var weatherHumidity: Int?
    public var weatherWindSpeed: Double?
    public var weatherWindDirection: String?
    public var weatherDescription: String?
    public var weatherTimestamp: Date?
    public var weather: String?
    public var cloudDirtyFlag: Bool = false

    /// Contest fields
    /// Contest identifier (matches ContestDefinition.id)
    public var contestId: String?
    /// Category: "SINGLE-OP", "MULTI-ONE", etc.
    public var contestCategory: String?
    /// Power level: "HIGH", "LOW", "QRP"
    public var contestPower: String?
    /// Band restriction: "ALL" or single band
    public var contestBands: String?
    /// Callsign override for multi-op
    public var contestOperator: String?

    /// Whether this session is a contest
    public var isContest: Bool {
        contestId != nil
    }

    public var hasSolarData: Bool {
        solarKIndex != nil || solarFlux != nil || solarSunspots != nil
    }

    public var hasWeatherData: Bool {
        weatherTemperatureF != nil
    }

    public var activationType: ActivationType {
        get { ActivationType(rawValue: activationTypeRawValue) ?? .casual }
        set { activationTypeRawValue = newValue.rawValue }
    }

    public var programs: Set<String> {
        get {
            guard !programsRawValue.isEmpty,
                  let data = programsRawValue.data(using: .utf8),
                  let slugs = try? JSONDecoder().decode([String].self, from: data)
            else {
                if activationTypeRawValue == "casual" || activationTypeRawValue.isEmpty {
                    return []
                }
                return [activationTypeRawValue]
            }
            return Set(slugs)
        }
        set {
            let sorted = newValue.sorted()
            if let data = try? JSONEncoder().encode(sorted) {
                programsRawValue = String(data: data, encoding: .utf8) ?? ""
            }
            if newValue.isEmpty {
                activationTypeRawValue = "casual"
            } else if newValue.count == 1, let first = newValue.first {
                activationTypeRawValue = first
            } else {
                activationTypeRawValue = sorted.first ?? "casual"
            }
        }
    }

    public var isPOTA: Bool {
        programs.contains("pota")
    }

    public var isSOTA: Bool {
        programs.contains("sota")
    }

    public var isWWFF: Bool {
        programs.contains("wwff")
    }

    public var isCasual: Bool {
        programs.isEmpty
    }

    public var programsDisplayName: String {
        if programs.isEmpty {
            return "Casual"
        }
        let names = programs.sorted().map { slug -> String in
            switch slug {
            case "pota": "POTA"
            case "sota": "SOTA"
            case "wwff": "WWFF"
            default: slug.uppercased()
            }
        }
        return names.joined(separator: " + ")
    }

    public var programsIcon: String {
        if isPOTA {
            return "tree"
        }
        if isWWFF {
            return "leaf.fill"
        }
        if isSOTA {
            return "mountain.2"
        }
        return "radio"
    }

    public var status: LoggingSessionStatus {
        get { LoggingSessionStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    public var spotComments: [POTASpotComment] {
        get {
            guard let data = spotCommentsData else {
                return []
            }
            return (try? JSONDecoder().decode([POTASpotComment].self, from: data)) ?? []
        }
        set { spotCommentsData = try? JSONEncoder().encode(newValue) }
    }

    public var roveStops: [RoveStop] {
        get {
            guard let data = roveStopsData else {
                return []
            }
            return (try? JSONDecoder().decode([RoveStop].self, from: data)) ?? []
        }
        set { roveStopsData = try? JSONEncoder().encode(newValue) }
    }

    public var currentRoveStop: RoveStop? {
        roveStops.last { $0.endedAt == nil } ?? roveStops.last
    }

    public var roveStopCount: Int {
        roveStops.count
    }

    public var uniqueParkCount: Int {
        Set(roveStops.map { $0.parkReference.uppercased() }).count
    }

    /// Rove stops merged by park (combines revisits into a single entry)
    public var mergedRoveStops: [RoveStop] {
        var seen: [String: Int] = [:]
        var merged: [RoveStop] = []

        for stop in roveStops.sorted(by: { $0.startedAt < $1.startedAt }) {
            let key = stop.parkReference.uppercased()
            if let idx = seen[key] {
                merged[idx].qsoCount += stop.qsoCount
                if stop.startedAt < merged[idx].startedAt {
                    merged[idx].startedAt = stop.startedAt
                }
                if let end = stop.endedAt {
                    if let existingEnd = merged[idx].endedAt {
                        merged[idx].endedAt = max(existingEnd, end)
                    } else {
                        merged[idx].endedAt = end
                    }
                } else {
                    merged[idx].endedAt = nil
                }
                if let grid = stop.myGrid {
                    merged[idx].myGrid = grid
                }
            } else {
                seen[key] = merged.count
                merged.append(stop)
            }
        }

        return merged
    }

    /// Total QSOs across all rove stops
    public var roveTotalQSOCount: Int {
        roveStops.reduce(0) { $0 + $1.qsoCount }
    }

    public var isActive: Bool {
        status == .active
    }

    public var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    public func end() {
        endedAt = Date()
        status = .completed
    }

    public func pause() {
        status = .paused
    }

    public func resume() {
        status = .active
    }

    public func incrementQSOCount() {
        qsoCount += 1
    }

    public func decrementQSOCount() {
        qsoCount = max(0, qsoCount - 1)
    }

    public func updateFrequency(_ freq: Double) {
        frequency = freq
    }

    public func updateMode(_ newMode: String) {
        mode = newMode.uppercased()
    }
}
