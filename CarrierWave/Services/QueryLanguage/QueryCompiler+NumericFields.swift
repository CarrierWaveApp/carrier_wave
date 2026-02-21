import CarrierWaveCore
import Foundation

// MARK: - QueryCompiler Numeric Field Compilation

extension QueryCompiler {
    // MARK: - Numeric Field Routing

    static func compileOptionalIntFieldTerm(
        field: QueryField, condition: TermCondition
    ) -> (QSO) -> Bool {
        switch field {
        case .dxcc: compileOptionalIntMatch(condition) { $0.dxcc }
        case .power: compileOptionalIntMatch(condition) { $0.power }
        default: { _ in true }
        }
    }

    // MARK: - Numeric Matching

    static func compileNumericMatch(
        _ condition: TermCondition, extractor: @escaping (QSO) -> Double?
    ) -> (QSO) -> Bool {
        switch condition {
        case let .greaterThan(value):
            return { extractor($0).map { $0 > value } ?? false }

        case let .lessThan(value):
            return { extractor($0).map { $0 < value } ?? false }

        case let .greaterThanOrEqual(value):
            return { extractor($0).map { $0 >= value } ?? false }

        case let .lessThanOrEqual(value):
            return { extractor($0).map { $0 <= value } ?? false }

        case let .numericRange(start, end):
            return { extractor($0).map { $0 >= start && $0 <= end } ?? false }

        case let .equals(value):
            if let num = Double(value) {
                // Exact match with small tolerance
                return { extractor($0).map { abs($0 - num) < 0.001 } ?? false }
            }
            return { _ in false }

        default:
            return { _ in true }
        }
    }

    static func compileOptionalIntMatch(
        _ condition: TermCondition, extractor: @escaping (QSO) -> Int?
    ) -> (QSO) -> Bool {
        switch condition {
        case let .greaterThan(value):
            let intVal = Int(value)
            return { extractor($0).map { $0 > intVal } ?? false }

        case let .lessThan(value):
            let intVal = Int(value)
            return { extractor($0).map { $0 < intVal } ?? false }

        case let .greaterThanOrEqual(value):
            let intVal = Int(value)
            return { extractor($0).map { $0 >= intVal } ?? false }

        case let .lessThanOrEqual(value):
            let intVal = Int(value)
            return { extractor($0).map { $0 <= intVal } ?? false }

        case let .numericRange(start, end):
            let intStart = Int(start)
            let intEnd = Int(end)
            return { extractor($0).map { $0 >= intStart && $0 <= intEnd } ?? false }

        case let .equals(value):
            if let num = Int(value) {
                return { extractor($0) == num }
            }
            return { _ in false }

        default:
            return { _ in true }
        }
    }
}
