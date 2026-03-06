import Foundation

// MARK: - ContestDefinition

/// Complete definition of a contest's rules, exchanges, scoring, and Cabrillo format.
public struct ContestDefinition: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: String,
        name: String,
        cabrilloCategoryContest: String,
        bands: [String],
        modes: [String],
        exchange: ContestExchange,
        multipliers: ContestMultipliers,
        scoring: ContestScoring,
        dupeRules: ContestDupeRules,
        cabrillo: CabrilloTemplate
    ) {
        self.id = id
        self.name = name
        self.cabrilloCategoryContest = cabrilloCategoryContest
        self.bands = bands
        self.modes = modes
        self.exchange = exchange
        self.multipliers = multipliers
        self.scoring = scoring
        self.dupeRules = dupeRules
        self.cabrillo = cabrillo
    }

    // MARK: Public

    public var id: String
    public var name: String
    public var cabrilloCategoryContest: String
    public var bands: [String]
    public var modes: [String]
    public var exchange: ContestExchange
    public var multipliers: ContestMultipliers
    public var scoring: ContestScoring
    public var dupeRules: ContestDupeRules
    public var cabrillo: CabrilloTemplate
}

// MARK: - ContestExchange

public struct ContestExchange: Codable, Sendable {
    // MARK: Lifecycle

    public init(fields: [ExchangeField]) {
        self.fields = fields
    }

    // MARK: Public

    public var fields: [ExchangeField]
}

// MARK: - ExchangeField

public struct ExchangeField: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: String,
        label: String,
        type: ExchangeFieldType,
        defaultValue: String? = nil,
        width: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.width = width
    }

    // MARK: Public

    public var id: String
    public var label: String
    public var type: ExchangeFieldType
    public var defaultValue: String?
    public var width: Int?
}

// MARK: - ExchangeFieldType

public enum ExchangeFieldType: String, Codable, Sendable {
    case rst
    case cqZone
    case ituZone
    case state
    case arrlSection
    case serialNumber
    case county
    case power
    case opaque
    case name
    case precedence
    case check
    case classField = "class"
}

// MARK: - ContestMultipliers

public struct ContestMultipliers: Codable, Sendable {
    // MARK: Lifecycle

    public init(types: [MultiplierType], perBand: Bool) {
        self.types = types
        self.perBand = perBand
    }

    // MARK: Public

    public var types: [MultiplierType]
    public var perBand: Bool
}

// MARK: - MultiplierType

public enum MultiplierType: String, Codable, Sendable {
    case dxcc
    case cqZone
    case ituZone
    case state
    case arrlSection
    case county
    case wpxPrefix
}

// MARK: - ContestScoring

public struct ContestScoring: Codable, Sendable {
    // MARK: Lifecycle

    public init(rules: [ScoringRule]) {
        self.rules = rules
    }

    // MARK: Public

    public var rules: [ScoringRule]
}

// MARK: - ScoringRule

public struct ScoringRule: Codable, Sendable {
    // MARK: Lifecycle

    public init(condition: ScoringCondition, points: Int) {
        self.condition = condition
        self.points = points
    }

    // MARK: Public

    public var condition: ScoringCondition
    public var points: Int
}

// MARK: - ScoringCondition

public enum ScoringCondition: String, Codable, Sendable {
    case sameCountry
    case sameContinent
    case differentContinent
    case sameDXCC
    case any
}

// MARK: - ContestDupeRules

public struct ContestDupeRules: Codable, Sendable {
    // MARK: Lifecycle

    public init(perBand: Bool, perMode: Bool) {
        self.perBand = perBand
        self.perMode = perMode
    }

    // MARK: Public

    public var perBand: Bool
    public var perMode: Bool
}

// MARK: - CabrilloTemplate

public struct CabrilloTemplate: Codable, Sendable {
    // MARK: Lifecycle

    public init(qsoTemplate: String, fieldWidths: [String: Int]) {
        self.qsoTemplate = qsoTemplate
        self.fieldWidths = fieldWidths
    }

    // MARK: Public

    public var qsoTemplate: String
    public var fieldWidths: [String: Int]
}
