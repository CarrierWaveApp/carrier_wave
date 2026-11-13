import CarrierWaveCore
import Foundation

// MARK: - ContestScoring

//
// Display projection of the v0.3 scoring pipeline, mapped from the FFI DTO.
// The scoring-pipeline views render this full tree; evaluation happens only
// in the Rust engine.

public struct ContestScoring: Sendable, Equatable {
    public let phases: [ContestScoringPhase]
}

// MARK: - ContestScoringPhase

public enum ContestScoringPhase: Sendable, Equatable {
    case perQSO(ContestPerQSOPhase)
    case multiplierCount(ContestMultiplierPhase)
    case aggregate(ContestAggregatePhase)

    // MARK: Public

    public var id: String {
        switch self {
        case let .perQSO(phase): phase.id
        case let .multiplierCount(phase): phase.id
        case let .aggregate(phase): phase.id
        }
    }

    public var description: String? {
        switch self {
        case let .perQSO(phase): phase.description
        case let .multiplierCount(phase): phase.description
        case let .aggregate(phase): phase.description
        }
    }
}

// MARK: - ContestPerQSOPhase

public struct ContestPerQSOPhase: Sendable, Equatable {
    public let id: String
    public let description: String?
    public let rules: [ContestScoringRule]
}

// MARK: - ContestMultiplierScope

public enum ContestMultiplierScope: String, Sendable {
    case perBand = "per_band"
    case perContest = "per_contest"
}

// MARK: - ContestMultiplierPhase

public struct ContestMultiplierPhase: Sendable, Equatable {
    public let id: String
    public let description: String?
    public let source: String
    public let scope: ContestMultiplierScope
    public let includeZeroPointQSOs: Bool
}

// MARK: - ContestAggregatePhase

public struct ContestAggregatePhase: Sendable, Equatable {
    public let id: String
    public let description: String?
    public let operation: ContestAggregateOp
}

// MARK: - ContestScoringRule

public struct ContestScoringRule: Sendable, Equatable {
    public let description: String?
    public let conditions: [ContestCondition]
    public let value: Int
}

// MARK: - ContestConditionOp

public enum ContestConditionOp: String, Sendable {
    case eq
    case ne
    case `in`
    case notIn = "not_in"
    case gt
    case gte
    case lt
    case lte
}

// MARK: - ContestCondition

public struct ContestCondition: Sendable, Equatable {
    public let field: String
    public let op: ContestConditionOp
    public let value: JSONValue?
    public let reference: String?
}

// MARK: - ContestAggregateOp

indirect public enum ContestAggregateOp: Sendable, Equatable {
    case reference(phase: String)
    case literal(Int)
    case add([ContestAggregateOp])
    case multiply([ContestAggregateOp])
    case max([ContestAggregateOp])
}

// MARK: - JSONValue

/// Polymorphic literal used by scoring-condition values (display only).
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case null

    // MARK: Public

    public var stringValue: String? {
        switch self {
        case let .string(value): value
        case let .int(value): String(value)
        case let .double(value):
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                String(Int(value))
            } else {
                String(value)
            }
        case let .bool(value): value ? "true" : "false"
        case .array,
             .null: nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(values) = self {
            return values
        }
        return nil
    }
}

// MARK: - FFI mapping

public extension FfiContestDefinition {
    var scoring: ContestScoring {
        ContestScoring(phases: scoringPhases.map(ContestScoringPhase.init(ffi:)))
    }
}

extension ContestScoringPhase {
    init(ffi: FfiContestScoringPhase) {
        switch ffi {
        case let .perQso(id, description, rules):
            self = .perQSO(ContestPerQSOPhase(
                id: id,
                description: description,
                rules: rules.map(ContestScoringRule.init(ffi:))
            ))
        case let .multiplierCount(id, description, source, perBand, includeZeroPointQsos):
            self = .multiplierCount(ContestMultiplierPhase(
                id: id,
                description: description,
                source: source,
                scope: perBand ? .perBand : .perContest,
                includeZeroPointQSOs: includeZeroPointQsos
            ))
        case let .aggregate(id, description, operation):
            self = .aggregate(ContestAggregatePhase(
                id: id,
                description: description,
                operation: ContestAggregateOp(ffi: operation)
            ))
        }
    }
}

extension ContestScoringRule {
    init(ffi: FfiContestScoringRule) {
        self.init(
            description: ffi.description,
            conditions: ffi.conditions.map(ContestCondition.init(ffi:)),
            value: Int(ffi.value)
        )
    }
}

extension ContestCondition {
    init(ffi: FfiContestCondition) {
        self.init(
            field: ffi.field,
            op: ContestConditionOp(rawValue: ffi.op) ?? .eq,
            value: ffi.value.map(JSONValue.init(ffi:)),
            reference: ffi.reference
        )
    }
}

extension ContestAggregateOp {
    init(ffi: FfiContestAggregateOp) {
        switch ffi {
        case let .reference(phase):
            self = .reference(phase: phase)
        case let .literal(value):
            self = .literal(Int(value))
        case let .add(inputs):
            self = .add(inputs.map(ContestAggregateOp.init(ffi:)))
        case let .multiply(inputs):
            self = .multiply(inputs.map(ContestAggregateOp.init(ffi:)))
        case let .max(inputs):
            self = .max(inputs.map(ContestAggregateOp.init(ffi:)))
        }
    }
}

extension JSONValue {
    init(ffi: FfiJsonValue) {
        switch ffi {
        case let .str(value):
            self = .string(value)
        case let .int(value):
            self = .int(Int(value))
        case let .double(value):
            self = .double(value)
        case let .bool(value):
            self = .bool(value)
        case let .array(values):
            self = .array(values.map(JSONValue.init(ffi:)))
        case .null:
            self = .null
        }
    }
}
