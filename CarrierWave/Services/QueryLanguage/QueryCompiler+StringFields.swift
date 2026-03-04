import CarrierWaveData
import Foundation

// MARK: - QueryCompiler String Field Compilation

extension QueryCompiler {
    // MARK: - String Field Routing

    static func compileStringFieldTerm(
        field: QueryField, condition: TermCondition
    ) -> (QSO) -> Bool {
        switch field {
        case .callsign: compileStringMatch(condition) { $0.callsign }
        case .band: compileStringMatch(condition) { $0.band }
        case .mode: compileStringMatch(condition) { $0.mode }
        case .myCallsign: compileStringMatch(condition) { $0.myCallsign }
        default: { _ in true }
        }
    }

    static func compileOptionalStringFieldTerm(
        field: QueryField, condition: TermCondition
    ) -> (QSO) -> Bool {
        switch field {
        case .park: compileOptionalStringMatch(condition) { $0.parkReference }
        case .sota: compileOptionalStringMatch(condition) { $0.sotaRef }
        case .grid: compileOptionalStringMatch(condition) { $0.theirGrid }
        case .state: compileOptionalStringMatch(condition) { $0.state }
        case .country: compileOptionalStringMatch(condition) { $0.country }
        case .name: compileOptionalStringMatch(condition) { $0.name }
        case .qth: compileOptionalStringMatch(condition) { $0.qth }
        case .notes: compileOptionalStringMatch(condition) { $0.notes }
        case .myGrid: compileOptionalStringMatch(condition) { $0.myGrid }
        default: { _ in true }
        }
    }

    // MARK: - String Matching

    static func compileStringMatch(
        _ condition: TermCondition, extractor: @escaping (QSO) -> String
    ) -> (QSO) -> Bool {
        switch condition {
        case let .equals(value):
            let lowered = value.lowercased()
            return { extractor($0).lowercased() == lowered }

        case let .contains(value):
            let lowered = value.lowercased()
            return { extractor($0).lowercased().contains(lowered) }

        case let .prefix(value):
            let lowered = value.lowercased()
            return { extractor($0).lowercased().hasPrefix(lowered) }

        case let .suffix(value):
            let lowered = value.lowercased()
            return { extractor($0).lowercased().hasSuffix(lowered) }

        case let .range(start, end):
            let lowStart = start.lowercased()
            let lowEnd = end.lowercased()
            return { qso in
                let val = extractor(qso).lowercased()
                return val >= lowStart && val <= lowEnd
            }

        default:
            return { _ in true }
        }
    }

    static func compileOptionalStringMatch(
        _ condition: TermCondition,
        extractor: @escaping (QSO) -> String?
    ) -> (QSO) -> Bool {
        switch condition {
        case let .equals(value):
            let lowered = value.lowercased()
            return { extractor($0)?.lowercased() == lowered }

        case let .contains(value):
            let lowered = value.lowercased()
            return { extractor($0)?.lowercased().contains(lowered) ?? false }

        case let .prefix(value):
            let lowered = value.lowercased()
            return { extractor($0)?.lowercased().hasPrefix(lowered) ?? false }

        case let .suffix(value):
            let lowered = value.lowercased()
            return { extractor($0)?.lowercased().hasSuffix(lowered) ?? false }

        case let .range(start, end):
            let lowStart = start.lowercased()
            let lowEnd = end.lowercased()
            return { qso in
                guard let val = extractor(qso)?.lowercased() else {
                    return false
                }
                return val >= lowStart && val <= lowEnd
            }

        default:
            return { _ in true }
        }
    }
}
