import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - ActivationType

/// Type of logging activation
enum ActivationType: String, Codable, CaseIterable {
    case casual
    case pota
    case sota
    case aoa
    case wwff

    // MARK: Internal

    var displayName: String {
        switch self {
        case .casual: "Casual"
        case .pota: "POTA"
        case .sota: "SOTA"
        case .aoa: "AoA"
        case .wwff: "WWFF"
        }
    }

    var icon: String {
        switch self {
        case .casual: "radio"
        case .pota: "tree"
        case .sota: "mountain.2"
        case .aoa: "eye"
        case .wwff: "leaf.fill"
        }
    }

    /// Derive activation type from selected programs set.
    /// Priority: pota > wwff > sota > aoa > casual
    static func from(programs: Set<String>) -> ActivationType {
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

/// Status of a logging session
enum LoggingSessionStatus: String, Codable {
    case active
    case paused
    case completed
}

// MARK: - LoggingSession

/// A logging session represents a period of operating, optionally at a specific activation
@Model
nonisolated final class LoggingSession {
    // MARK: Lifecycle

    init(
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
        attendees: String? = nil
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

        // Set programs from explicit parameter, or derive from activationType
        if !programs.isEmpty {
            self.programs = programs
        } else if activationType != .casual {
            self.programs = [activationType.rawValue]
        }
    }

    // MARK: Internal

    var id = UUID()
    var myCallsign = ""
    var startedAt = Date()
    var endedAt: Date?

    /// Operating frequency in MHz (e.g., 14.060)
    var frequency: Double?

    /// Operating mode (CW, SSB, FT8, etc.)
    var mode = "CW"

    /// Stored as raw value for SwiftData compatibility
    var activationTypeRawValue: String = ActivationType.casual.rawValue

    /// Programs active in this session, stored as JSON array of slugs (e.g., ["pota","sota"]).
    /// Empty array = casual. Replaces activationTypeRawValue as source of truth.
    var programsRawValue: String = ""

    /// Session status stored as raw value
    var statusRawValue: String = LoggingSessionStatus.active.rawValue

    /// POTA park reference (e.g., "K-1234")
    var parkReference: String?

    /// SOTA summit reference (e.g., "W4C/CM-001")
    var sotaReference: String?

    /// AoA mission reference (e.g., "M-a01f")
    var missionReference: String?

    /// WWFF flora & fauna reference (e.g., "KFF-1234")
    var wwffReference: String?

    /// Operator's grid square
    var myGrid: String?

    /// Transmit power in watts
    var power: Int?

    /// Radio/rig name (e.g., "Elecraft KX3")
    var myRig: String?

    /// Session notes
    var notes: String?

    /// Custom title set by user (overrides displayTitle)
    var customTitle: String?

    /// Number of QSOs logged in this session
    var qsoCount: Int = 0

    /// Serialized spot comments JSON (stored as Data for SwiftData compatibility)
    var spotCommentsData: Data?

    // MARK: - Rove

    /// Whether this session is a POTA rove (multiple park stops)
    var isRove: Bool = false

    /// Serialized rove stops JSON (stored as Data for SwiftData compatibility)
    var roveStopsData: Data?

    // MARK: - Equipment

    /// Antenna used (e.g., "EFHW", "Buddipole")
    var myAntenna: String?

    /// CW key used (e.g., "Begali Adventure")
    var myKey: String?

    /// Microphone used (e.g., "Heil Pro 7")
    var myMic: String?

    /// Additional equipment notes
    var extraEquipment: String?

    // MARK: - People

    /// Comma-separated attendees/operators
    var attendees: String?

    // MARK: - Photos

    /// Photo filenames relative to SessionPhotos/<sessionUUID>/
    var photoFilenames: [String] = []

    // MARK: - Conditions (recorded at session start)

    var solarKIndex: Double?
    var solarFlux: Double?
    var solarSunspots: Int?
    var solarPropagationRating: String?
    var solarAIndex: Int?
    var solarBandConditions: String?
    var solarTimestamp: Date?
    var solarConditions: String?
    var weatherTemperatureF: Double?
    var weatherTemperatureC: Double?
    var weatherHumidity: Int?
    var weatherWindSpeed: Double?
    var weatherWindDirection: String?
    var weatherDescription: String?
    var weatherTimestamp: Date?
    var weather: String?

    /// Whether this record has local changes not yet synced to iCloud.
    var cloudDirtyFlag: Bool = false

    /// Whether structured solar data is available
    var hasSolarData: Bool {
        solarKIndex != nil || solarFlux != nil || solarSunspots != nil
    }

    /// Whether structured weather data is available
    var hasWeatherData: Bool {
        weatherTemperatureF != nil
    }

    /// Activation type enum accessor
    var activationType: ActivationType {
        get { ActivationType(rawValue: activationTypeRawValue) ?? .casual }
        set { activationTypeRawValue = newValue.rawValue }
    }

    /// The set of active programs for this session.
    /// Reads from programsRawValue if set, otherwise migrates from activationTypeRawValue.
    var programs: Set<String> {
        get {
            guard !programsRawValue.isEmpty,
                  let data = programsRawValue.data(using: .utf8),
                  let slugs = try? JSONDecoder().decode([String].self, from: data)
            else {
                // Migration: derive from old activationTypeRawValue
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
            // Keep activationTypeRawValue in sync for backward compat
            if newValue.isEmpty {
                activationTypeRawValue = "casual"
            } else if newValue.count == 1, let first = newValue.first {
                activationTypeRawValue = first
            } else {
                activationTypeRawValue = sorted.first ?? "casual"
            }
        }
    }

    /// Whether this is a POTA activation
    var isPOTA: Bool {
        programs.contains("pota")
    }

    /// Whether this is a SOTA activation
    var isSOTA: Bool {
        programs.contains("sota")
    }

    /// Whether this is a WWFF activation
    var isWWFF: Bool {
        programs.contains("wwff")
    }

    /// Whether this is a casual (no-program) session
    var isCasual: Bool {
        programs.isEmpty
    }

    /// Display name for the session's programs (e.g., "POTA", "POTA + SOTA", "Casual")
    var programsDisplayName: String {
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

    /// Icon for the session's primary program
    var programsIcon: String {
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

    /// Session status enum accessor
    var status: LoggingSessionStatus {
        get { LoggingSessionStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    /// Spot comments from the session (decoded from JSON data)
    var spotComments: [POTASpotComment] {
        get {
            guard let data = spotCommentsData else {
                return []
            }
            return (try? JSONDecoder().decode([POTASpotComment].self, from: data)) ?? []
        }
        set {
            spotCommentsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Rove stops (decoded from JSON data)
    var roveStops: [RoveStop] {
        get {
            guard let data = roveStopsData else {
                return []
            }
            return (try? JSONDecoder().decode([RoveStop].self, from: data)) ?? []
        }
        set {
            roveStopsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// The currently active rove stop (last one without an endedAt)
    var currentRoveStop: RoveStop? {
        roveStops.last { $0.endedAt == nil } ?? roveStops.last
    }

    /// Number of rove stops (raw, including revisits)
    var roveStopCount: Int {
        roveStops.count
    }

    /// Number of unique parks visited in a rove
    var uniqueParkCount: Int {
        Set(roveStops.map { $0.parkReference.uppercased() }).count
    }

    /// Rove stops merged by park (combines revisits into a single entry)
    var mergedRoveStops: [RoveStop] {
        var seen: [String: Int] = [:]
        var merged: [RoveStop] = []

        for stop in roveStops.sorted(by: { $0.startedAt < $1.startedAt }) {
            let key = stop.parkReference.uppercased()
            if let idx = seen[key] {
                // Merge into existing: extend time range, sum QSO counts
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
                    merged[idx].endedAt = nil // still active
                }
                // Keep latest grid
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
    var roveTotalQSOCount: Int {
        roveStops.reduce(0) { $0 + $1.qsoCount }
    }

    /// Whether the session is currently active
    var isActive: Bool {
        status == .active
    }

    /// Session duration
    var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    // MARK: - Methods

    /// End the session
    func end() {
        endedAt = Date()
        status = .completed
    }

    /// Pause the session
    func pause() {
        status = .paused
    }

    /// Resume a paused session
    func resume() {
        status = .active
    }

    /// Increment QSO count
    func incrementQSOCount() {
        qsoCount += 1
    }

    /// Decrement QSO count (when a QSO is hidden/deleted)
    func decrementQSOCount() {
        qsoCount = max(0, qsoCount - 1)
    }

    /// Update operating frequency
    func updateFrequency(_ freq: Double) {
        frequency = freq
    }

    /// Update operating mode
    func updateMode(_ newMode: String) {
        mode = newMode.uppercased()
    }
}
