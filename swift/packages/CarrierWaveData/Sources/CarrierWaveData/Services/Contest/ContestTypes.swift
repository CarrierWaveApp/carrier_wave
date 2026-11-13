import CarrierWaveCore
import Foundation

// MARK: - ContestQSORecord

/// Lightweight Sendable snapshot of a QSO for contest engine processing.
/// Includes derived fields (country, continent, zones) resolved by the caller
/// before registration — the engine doesn't perform country-file lookups.
/// Scoring happens in the Rust engine; this is the host-side input shape.
public struct ContestQSORecord: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        band: String,
        mode: String,
        timestamp: Date,
        sentExchange: [String: String] = [:],
        receivedExchange: [String: String] = [:],
        serialSent: Int? = nil,
        serialReceived: Int? = nil,
        theirCountry: String? = nil,
        theirContinent: String? = nil,
        theirCQZone: Int? = nil,
        theirITUZone: Int? = nil,
        distanceKm: Double? = nil
    ) {
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.timestamp = timestamp
        self.sentExchange = sentExchange
        self.receivedExchange = receivedExchange
        self.serialSent = serialSent
        self.serialReceived = serialReceived
        self.theirCountry = theirCountry
        self.theirContinent = theirContinent
        self.theirCQZone = theirCQZone
        self.theirITUZone = theirITUZone
        self.distanceKm = distanceKm
    }

    // MARK: Public

    public var callsign: String
    public var band: String
    public var mode: String
    public var timestamp: Date
    public var sentExchange: [String: String]
    public var receivedExchange: [String: String]
    public var serialSent: Int?
    public var serialReceived: Int?

    /// Derived fields populated by the caller (via CTYService / prefix lookup).
    public var theirCountry: String?
    public var theirContinent: String?
    public var theirCQZone: Int?
    public var theirITUZone: Int?
    public var distanceKm: Double?

    /// Collapsed mode group: `CW`, `PHONE`, or `DIGITAL`.
    public var modeGroup: String {
        Self.modeGroup(for: mode)
    }

    public static func modeGroup(for mode: String) -> String {
        contestModeGroup(mode: mode)
    }

    // MARK: Internal

    var ffiInput: FfiContestQsoInput {
        FfiContestQsoInput(
            callsign: callsign,
            band: band,
            mode: mode,
            timestamp: Int64(timestamp.timeIntervalSince1970),
            sentExchange: sentExchange,
            receivedExchange: receivedExchange,
            serialSent: serialSent.map(Int64.init),
            serialReceived: serialReceived.map(Int64.init),
            theirCountry: theirCountry,
            theirContinent: theirContinent,
            theirCqZone: theirCQZone.map(Int64.init),
            theirItuZone: theirITUZone.map(Int64.init),
            distanceKm: distanceKm
        )
    }
}

// MARK: - MyStationContext

/// Operating-station context used by the contest engine to evaluate
/// scoring conditions that reference `my_*` fields.
public struct MyStationContext: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        callsign: String,
        country: String? = nil,
        continent: String? = nil,
        cqZone: Int? = nil,
        ituZone: Int? = nil,
        grid: String? = nil,
        state: String? = nil,
        province: String? = nil,
        section: String? = nil,
        power: String? = nil,
        classLabel: String? = nil,
        name: String? = nil
    ) {
        self.callsign = callsign
        self.country = country
        self.continent = continent?.uppercased()
        self.cqZone = cqZone
        self.ituZone = ituZone
        self.grid = grid?.uppercased()
        self.state = state?.uppercased()
        self.province = province?.uppercased()
        self.section = section?.uppercased()
        self.power = power?.uppercased()
        self.classLabel = classLabel?.uppercased()
        self.name = name
    }

    // MARK: Public

    public var callsign: String
    public var country: String?
    public var continent: String?
    public var cqZone: Int?
    public var ituZone: Int?
    public var grid: String?
    public var state: String?
    public var province: String?
    public var section: String?
    public var power: String?
    public var classLabel: String?
    public var name: String?

    /// Value for a given `station_*` autofill source, if available.
    public func autofillValue(for source: String) -> String? {
        switch source {
        case "station_cq_zone": cqZone.map(String.init)
        case "station_itu_zone": ituZone.map(String.init)
        case "station_country": country
        case "station_continent": continent
        case "station_section": section
        case "station_state": state
        case "station_province": province
        case "station_grid": grid
        case "station_power": power
        case "station_class": classLabel
        case "station_name": name
        default: nil
        }
    }

    // MARK: Internal

    var ffi: FfiMyStation {
        FfiMyStation(
            callsign: callsign,
            country: country,
            continent: continent,
            cqZone: cqZone.map(Int64.init),
            ituZone: ituZone.map(Int64.init),
            grid: grid,
            state: state,
            province: province,
            section: section,
            power: power,
            classLabel: classLabel,
            name: name
        )
    }
}

// MARK: - ContestDupeStatus

/// Result of checking or registering a QSO against the contest engine.
public enum ContestDupeStatus: Sendable, Equatable {
    case newStation
    case newMultiplier(phaseID: String, value: String)
    case dupe

    // MARK: Lifecycle

    init(ffi: FfiContestDupeStatus) {
        switch ffi {
        case .newStation:
            self = .newStation
        case let .newMultiplier(phaseId, value):
            self = .newMultiplier(phaseID: phaseId, value: value)
        case .dupe:
            self = .dupe
        }
    }
}

// MARK: - ContestScoreSnapshot

/// Current contest score state.
public struct ContestScoreSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        totalQSOs: Int = 0,
        totalPoints: Int = 0,
        multiplierCount: Int = 0,
        finalScore: Int = 0,
        qsosByBand: [String: Int] = [:],
        pointsByBand: [String: Int] = [:],
        multsByBand: [String: Int] = [:],
        dupeCount: Int = 0,
        phaseResults: [String: Int] = [:]
    ) {
        self.totalQSOs = totalQSOs
        self.totalPoints = totalPoints
        self.multiplierCount = multiplierCount
        self.finalScore = finalScore
        self.qsosByBand = qsosByBand
        self.pointsByBand = pointsByBand
        self.multsByBand = multsByBand
        self.dupeCount = dupeCount
        self.phaseResults = phaseResults
    }

    init(ffi: FfiContestScore) {
        totalQSOs = Int(ffi.totalQsos)
        totalPoints = Int(ffi.totalPoints)
        multiplierCount = Int(ffi.multiplierCount)
        finalScore = Int(ffi.finalScore)
        qsosByBand = ffi.qsosByBand.mapValues(Int.init)
        pointsByBand = ffi.pointsByBand.mapValues(Int.init)
        multsByBand = ffi.multsByBand.mapValues(Int.init)
        dupeCount = Int(ffi.dupeCount)
        phaseResults = ffi.phaseResults.mapValues(Int.init)
    }

    // MARK: Public

    public var totalQSOs: Int
    public var totalPoints: Int
    public var multiplierCount: Int
    public var finalScore: Int
    public var qsosByBand: [String: Int]
    public var pointsByBand: [String: Int]
    public var multsByBand: [String: Int]
    public var dupeCount: Int
    /// Per-phase integer result, keyed by phase id.
    public var phaseResults: [String: Int]

    // MARK: Internal

    var ffi: FfiContestScore {
        FfiContestScore(
            totalQsos: Int64(totalQSOs),
            totalPoints: Int64(totalPoints),
            multiplierCount: Int64(multiplierCount),
            finalScore: Int64(finalScore),
            qsosByBand: qsosByBand.mapValues(Int64.init),
            pointsByBand: pointsByBand.mapValues(Int64.init),
            multsByBand: multsByBand.mapValues(Int64.init),
            dupeCount: Int64(dupeCount),
            phaseResults: phaseResults.mapValues(Int64.init)
        )
    }
}

// MARK: - ContestOperatingMode

public enum ContestOperatingMode: String, Sendable {
    case cq
    case sp
}
