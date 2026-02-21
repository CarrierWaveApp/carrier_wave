import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - QueryCompiler Predicate Extraction

extension QueryCompiler {
    // MARK: - Predicate Extraction (for FetchDescriptor optimization)

    static func extractPredicate(_ expression: QueryExpression) -> Predicate<QSO>? {
        // For now, we only extract simple single-term predicates
        // Complex boolean logic falls back to post-fetch filtering

        guard case let .term(term) = expression else {
            // For AND expressions, we could potentially extract the first indexed term
            if case let .and(exprs) = expression {
                for expr in exprs {
                    if let predicate = extractPredicate(expr) {
                        return predicate
                    }
                }
            }
            return nil
        }

        guard let field = term.field, field.isIndexed else {
            return nil
        }

        // Extract predicates for indexed fields
        switch field {
        case .callsign:
            return extractCallsignPredicate(term.condition)

        case .band:
            return extractBandPredicate(term.condition)

        case .mode:
            return extractModePredicate(term.condition)

        case .date,
             .after,
             .before:
            return extractDatePredicate(field: field, condition: term.condition)

        default:
            return nil
        }
    }

    private static func extractCallsignPredicate(_ condition: TermCondition) -> Predicate<QSO>? {
        // Callsigns are stored in uppercase
        switch condition {
        case let .equals(value):
            let upper = value.uppercased()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.callsign == upper
            }
        case let .prefix(value):
            let upper = value.uppercased()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.callsign.starts(with: upper)
            }
        default:
            return nil
        }
    }

    private static func extractBandPredicate(_ condition: TermCondition) -> Predicate<QSO>? {
        // Bands are stored in lowercase (e.g., "6m", "20m")
        switch condition {
        case let .equals(value):
            let lower = value.lowercased()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.band == lower
            }
        case let .prefix(value):
            let lower = value.lowercased()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.band.starts(with: lower)
            }
        default:
            return nil
        }
    }

    private static func extractModePredicate(_ condition: TermCondition) -> Predicate<QSO>? {
        // Modes are stored in uppercase
        switch condition {
        case let .equals(value):
            let upper = value.uppercased()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.mode == upper
            }
        case let .prefix(value):
            let upper = value.uppercased()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.mode.starts(with: upper)
            }
        default:
            return nil
        }
    }

    private static func extractDatePredicate(field: QueryField, condition: TermCondition)
        -> Predicate<QSO>?
    {
        switch condition {
        case let .dateEquals(dateMatch):
            let (start, end) = dateMatch.resolve()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.timestamp >= start && qso.timestamp < end
            }

        case let .dateAfter(dateMatch):
            let (start, _) = dateMatch.resolve()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.timestamp >= start
            }

        case let .dateBefore(dateMatch):
            let (_, end) = dateMatch.resolve()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.timestamp < end
            }

        case let .dateRange(startMatch, endMatch):
            let (start, _) = startMatch.resolve()
            let (_, end) = endMatch.resolve()
            return #Predicate<QSO> { qso in
                !qso.isHidden && qso.timestamp >= start && qso.timestamp < end
            }

        default:
            return nil
        }
    }
}

// MARK: - Predicate Helpers

extension QueryCompiler {
    /// Build predicates that include the !isHidden check
    static func predicateWithHidden(_ basePredicate: Predicate<QSO>?) -> Predicate<QSO> {
        // SwiftData doesn't support runtime predicate composition,
        // so we need to bake !isHidden into each specific predicate
        basePredicate ?? #Predicate<QSO> { !$0.isHidden }
    }

    /// Build a predicate for callsign prefix search (includes !isHidden)
    static func callsignPrefixPredicate(_ prefix: String) -> Predicate<QSO> {
        let upper = prefix.uppercased()
        return #Predicate<QSO> { qso in
            !qso.isHidden && qso.callsign.starts(with: upper)
        }
    }

    /// Build a predicate for date range (includes !isHidden)
    static func dateRangePredicate(start: Date, end: Date) -> Predicate<QSO> {
        #Predicate<QSO> { qso in
            !qso.isHidden && qso.timestamp >= start && qso.timestamp < end
        }
    }

    /// Build a predicate for date after (includes !isHidden)
    static func dateAfterPredicate(_ date: Date) -> Predicate<QSO> {
        #Predicate<QSO> { qso in
            !qso.isHidden && qso.timestamp >= date
        }
    }

    /// Build a predicate for band filter (includes !isHidden)
    static func bandPredicate(_ band: String) -> Predicate<QSO> {
        let upper = band.uppercased()
        return #Predicate<QSO> { qso in
            !qso.isHidden && qso.band == upper
        }
    }

    /// Build a predicate for mode filter (includes !isHidden)
    static func modePredicate(_ mode: String) -> Predicate<QSO> {
        let upper = mode.uppercased()
        return #Predicate<QSO> { qso in
            !qso.isHidden && qso.mode == upper
        }
    }
}
