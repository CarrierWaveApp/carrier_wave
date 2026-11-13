import CarrierWaveCore
import Foundation

// MARK: - Contest definition facade

//
// The contest engine lives in the Rust core (`cw_domain::contest`, exposed via
// `cw-ffi`'s `ContestApi` / `ContestEngineApi`). The definition model the UI
// renders is the FFI display DTO; these typealiases + extensions keep the
// original Swift property surface (`definition.exchange.received`,
// `.dupeRules.scope`, `.operatingConstraints?.offTime`, …) so consumers stay
// source-compatible. Parsing, caching, and all behavior are Rust-owned —
// nothing here interprets the v0.3 format.

public typealias ContestDefinition = FfiContestDefinition
public typealias ContestDefinitionSummary = FfiContestSummary
public typealias ContestExchangeField = FfiContestExchangeField
public typealias ContestCategory = FfiContestCategory
public typealias ContestOverlayCategory = FfiContestOverlayCategory

// MARK: - ContestSponsor

public struct ContestSponsor: Sendable, Equatable {
    public let name: String?
    public let url: String?
}

// MARK: - ContestExchange

public struct ContestExchange: Sendable, Equatable {
    public let sent: [ContestExchangeField]
    public let received: [ContestExchangeField]
}

// MARK: - ContestExchangeFieldType

/// Known field types from the contest-definitions spec (v0.3). Unknown types
/// map to `.unknown(raw)`. Vocabulary only — matching happens in Rust.
public enum ContestExchangeFieldType: Sendable, Equatable, Hashable {
    case text
    case signalReport
    case serialNumber
    case cqZone
    case ituZone
    case gridSquare
    case stateProvince
    case arrlSection
    case sectionList
    case power
    case name
    case age
    case classField
    case unknown(String)

    // MARK: Public

    public var rawValue: String {
        switch self {
        case .text: "text"
        case .signalReport: "signal_report"
        case .serialNumber: "serial_number"
        case .cqZone: "cq_zone"
        case .ituZone: "itu_zone"
        case .gridSquare: "grid_square"
        case .stateProvince: "state_province"
        case .arrlSection: "arrl_section"
        case .sectionList: "section_list"
        case .power: "power"
        case .name: "name"
        case .age: "age"
        case .classField: "class"
        case let .unknown(raw): raw
        }
    }

    public static func from(raw: String) -> Self {
        switch raw {
        case "text": .text
        case "signal_report": .signalReport
        case "serial_number": .serialNumber
        case "cq_zone": .cqZone
        case "itu_zone": .ituZone
        case "grid_square": .gridSquare
        case "state_province": .stateProvince
        case "arrl_section": .arrlSection
        case "section_list": .sectionList
        case "power": .power
        case "name": .name
        case "age": .age
        case "class": .classField
        default: .unknown(raw)
        }
    }
}

// MARK: - ContestExchangeDefault

/// String form of an exchange-field default (the Rust side normalizes
/// numbers/bools the way the old Codable model did).
public struct ContestExchangeDefault: Sendable, Equatable {
    public let stringValue: String
}

public extension FfiContestExchangeField {
    /// Typed view over the raw `fieldType` string.
    var type: ContestExchangeFieldType {
        ContestExchangeFieldType.from(raw: fieldType)
    }

    var defaultValue: ContestExchangeDefault? {
        defaultValueString.map(ContestExchangeDefault.init(stringValue:))
    }
}

// MARK: - ContestDupeScope

public enum ContestDupeScope: String, Sendable {
    case session
    case contest
}

// MARK: - ContestDupeRules

public struct ContestDupeRules: Sendable, Equatable {
    public let scope: ContestDupeScope
    public let key: [String]
}

// MARK: - ContestOffTimeRules

public struct ContestOffTimeRules: Sendable, Equatable {
    public let minimumOffMinutes: Int?
    public let maximumOnHoursByCategory: [String: Double]
}

// MARK: - ContestBandChangeRules

public struct ContestBandChangeRules: Sendable, Equatable {
    public let appliesTo: [String]
    public let minMinutesOnBand: Int?
    public let maxChangesPerClockHour: Int?
}

// MARK: - ContestOperatingConstraints

public struct ContestOperatingConstraints: Sendable, Equatable {
    public let offTime: ContestOffTimeRules?
    public let bandChanges: ContestBandChangeRules?
}

// MARK: - ContestSchedule

/// Opaque schedule handle — only ever handed to `ContestScheduleEvaluator`,
/// which resolves occurrences in Rust from the definition body.
public struct ContestSchedule: Sendable, Equatable {
    let rawJson: String
}

// MARK: - Definition property surface

public extension FfiContestDefinition {
    var sponsor: ContestSponsor? {
        if sponsorName == nil, sponsorUrl == nil {
            return nil
        }
        return ContestSponsor(name: sponsorName, url: sponsorUrl)
    }

    var exchange: ContestExchange {
        ContestExchange(sent: exchangeSent, received: exchangeReceived)
    }

    var dupeRules: ContestDupeRules {
        ContestDupeRules(
            scope: ContestDupeScope(rawValue: dupeScope) ?? .contest,
            key: dupeKey
        )
    }

    var operatingConstraints: ContestOperatingConstraints? {
        let offTime: ContestOffTimeRules? = hasOffTimeRules
            ? ContestOffTimeRules(
                minimumOffMinutes: offTimeMinimumOffMinutes.map(Int.init),
                maximumOnHoursByCategory: offTimeMaxOnHoursByCategory
            )
            : nil
        let bandChanges: ContestBandChangeRules? = hasBandChangeRules
            ? ContestBandChangeRules(
                appliesTo: bandChangeAppliesTo,
                minMinutesOnBand: bandChangeMinMinutesOnBand.map(Int.init),
                maxChangesPerClockHour: bandChangeMaxChangesPerClockHour.map(Int.init)
            )
            : nil
        if offTime == nil, bandChanges == nil {
            return nil
        }
        return ContestOperatingConstraints(offTime: offTime, bandChanges: bandChanges)
    }

    var schedule: ContestSchedule {
        ContestSchedule(rawJson: rawJson)
    }
}

// MARK: - Parsing

/// Display projection of a raw v0.3 definition body (Rust-parsed).
public func contestDefinition(fromJson json: String) throws -> ContestDefinition {
    try contestDefinitionFromJson(json: json)
}
