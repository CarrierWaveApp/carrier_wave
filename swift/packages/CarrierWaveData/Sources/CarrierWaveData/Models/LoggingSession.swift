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
    case tota

    // MARK: Public

    public var displayName: String {
        switch self {
        case .casual: "Casual"
        case .pota: "POTA"
        case .sota: "SOTA"
        case .aoa: "AoA"
        case .wwff: "WWFF"
        case .tota: "TOTA"
        }
    }

    public var icon: String {
        switch self {
        case .casual: "radio"
        case .pota: "tree"
        case .sota: "mountain.2"
        case .aoa: "eye"
        case .wwff: "leaf.fill"
        case .tota: "square.grid.3x3.fill"
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
        if programs.contains("tota") {
            return .tota
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

// MARK: - TrackPoint

/// One sample of the operator's location during a session. Persisted as a JSON
/// blob on `LoggingSession.trackPointsData` so we don't pay relationship cost
/// for what's effectively an append-only trail.
public struct TrackPoint: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(timestamp: Date, latitude: Double, longitude: Double, elevationMeters: Double? = nil) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
    }

    // MARK: Public

    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let elevationMeters: Double?
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
        contestOverlayCategory: String? = nil,
        contestPower: String? = nil,
        contestBands: String? = nil,
        contestOperator: String? = nil,
        stationCallsign: String? = nil
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
        self.contestOverlayCategory = contestOverlayCategory
        self.contestPower = contestPower
        self.contestBands = contestBands
        self.contestOperator = contestOperator
        self.stationCallsign = stationCallsign

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
    public var qsoComment: String? // Prepended to every QSO's notes.
    public var customTitle: String?
    public var qsoCount: Int = 0
    public var spotCommentsData: Data?
    public var isRove: Bool = false
    /// TRANSITIONAL — the structured cw-store `rove_stop` table is the portable
    /// source of truth (the Rust split reads/writes it; the seam write-through
    /// keeps it in lockstep). This blob remains only for the CloudKit replica and
    /// the iOS UI reads; drop it when the sessions entity flips Rust-authoritative
    /// and rove-stop sync is decided (own entity vs re-embed).
    public var roveStopsData: Data?
    public var myAntenna: String?
    public var myKey: String?
    public var myMic: String?
    public var extraEquipment: String?
    public var attendees: String?
    public var photoFilenames: [String] = []

    /// Local-only FK to the `EquipmentItem` selected as the session's
    /// radio. `myRig` is the canonical export field.
    public var radioItemID: UUID?

    /// Club/alternate callsign used over the air (nil = operator is the station)
    public var stationCallsign: String?

    /// JSON-encoded array of additional operator callsigns (multi-op sessions)
    public var operatorCallsignsRawValue: String = "[]"

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

    // Contest fields
    public var contestId: String? // Matches ContestDefinition.id.
    public var contestCategory: String? // Primary category (e.g. "SOAB-HP").
    public var contestOverlayCategory: String? // e.g. "YL", "ROOKIE".
    public var contestPower: String? // "HIGH", "LOW", "QRP", or custom.
    public var contestBands: String? // "ALL" or single band.
    public var contestOperator: String? // Callsign override for multi-op.

    // MARK: - TOTA fields

    /// Activation site latitude (decimal degrees). Currently used by TOTA.
    public var activationLatitude: Double?
    /// Activation site longitude (decimal degrees). Currently used by TOTA.
    public var activationLongitude: Double?
    /// Distance travelled to/at the site, miles. Auto-filled from a recorded
    /// GPX track when present, otherwise user-entered. TOTA scoring base.
    public var activationDistanceMiles: Double?
    /// Elevation gain in feet. Auto-filled from track when present.
    public var activationElevationGainFeet: Double?
    /// Pack weight in pounds for the TOTA ruck bonus (+5 % per 5 lb).
    public var ruckWeightPounds: Double?
    /// Set when the operator stayed at ≤ 10 W for the entire session (TOTA QRP 2× multiplier).
    public var qrpActivation: Bool = false
    /// TOTA bonus toggles. Server-side scoring reads these directly.
    public var withPets: Bool = false
    public var withKids: Bool = false
    public var winlinkSent: Bool = false
    public var aprsSent: Bool = false
    /// VarAC VMail / email sent over RF (TOTA flat +5 pts).
    public var varacSent: Bool = false
    /// TOTA "adaptive sport" descriptor. No scoring change, display only.
    public var adaptiveSport: Bool = false
    /// JSON-encoded `[TrackPoint]` (timestamp + lat/lon/elev) recorded during the session.
    /// Stored as a blob to avoid maintaining a SwiftData relationship for what is
    /// effectively a write-once trail. Caller is responsible for thinning before write.
    public var trackPointsData: Data?

    /// TOTA category — `.standard` (default, full formula) or `.mobile` (separate
    /// leaderboard, simpler formula: QSOs × QRP + flats; no distance/percentage
    /// bonuses). Stored raw; access via `totaCategory`.
    public var totaCategoryRawValue: String?

    /// Personal Effort Factor 1...10. Multiplies the distance term in the score
    /// (and therefore percentage bonuses). Frozen at session start. Affects only
    /// the Personal Effort leaderboard. nil = not opted in.
    public var personalEffortFactor: Int?

    /// Operator-asserted: this is the very first activation of the tile by anyone.
    /// Server cannot confirm pre-upload; treated as "Asserted" tier in the ledger.
    public var firstActivationOfTileEver: Bool = false

    /// Operator override of the auto-detected winter flag. nil = use auto-detect
    /// (hemisphere + month). Bool = explicit user choice.
    public var winterActivationOverride: Bool?

    /// JSON-encoded `[String]` of 6-char Maidenhead tiles activated this session.
    /// Cached at session end from QSO-anchored tile detection over `trackPoints`
    /// + `activationLatitude/Longitude`. Recompute on track/QSO change.
    public var tilesActivatedData: Data?

    /// JSON-encoded `[T3Candidate]` — Tile-to-Tile candidates from spot
    /// correlation against the TOTA spots feed. Cached at session end so the
    /// summary log doesn't depend on the spots feed (rolling ~168h).
    public var totaT3CandidatesData: Data?

    /// When `totaT3CandidatesData` was last refreshed. Used by the detail view
    /// to decide whether to offer a lazy refresh (>5 min stale).
    public var totaT3SnapshotAt: Date?

    /// Server-returned official points after a successful TOTA upload. nil
    /// pre-upload. When non-nil, the in-app score headline is replaced with
    /// this value and editable fields lock.
    public var totaOfficialPoints: Double?

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
        if isTOTA {
            return "square.grid.3x3.fill"
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

    /// Recorded GPS track points. Reads/writes the JSON blob in `trackPointsData`.
    public var trackPoints: [TrackPoint] {
        get {
            guard let data = trackPointsData else {
                return []
            }
            return (try? JSONDecoder().decode([TrackPoint].self, from: data)) ?? []
        }
        set { trackPointsData = try? JSONEncoder().encode(newValue) }
    }

    /// TOTA category — defaults to `.standard` when the raw value is nil.
    public var totaCategory: TOTACategory {
        get { TOTACategory(rawValue: totaCategoryRawValue ?? "") ?? .standard }
        set { totaCategoryRawValue = newValue.rawValue }
    }

    /// 6-char Maidenhead tiles activated this session.
    public var tilesActivated: [String] {
        get {
            guard let data = tilesActivatedData else {
                return []
            }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set { tilesActivatedData = try? JSONEncoder().encode(newValue) }
    }

    /// Cached T3 candidate snapshot from the TOTA spots feed.
    public var totaT3Candidates: [T3Candidate] {
        get {
            guard let data = totaT3CandidatesData else {
                return []
            }
            return (try? JSONDecoder().decode([T3Candidate].self, from: data)) ?? []
        }
        set { totaT3CandidatesData = try? JSONEncoder().encode(newValue) }
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

public extension LoggingSession {
    var isTOTA: Bool {
        programs.contains("tota")
    }
}
