import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - QueryCompiler

// swiftlint:disable file_length type_body_length cyclomatic_complexity

/// Compiles a parsed query into a filter function for QSOs
///
/// Note: SwiftData's #Predicate macro doesn't support runtime construction,
/// so we compile to a closure-based filter. For indexed fields, we also
/// provide a FetchDescriptor with predicates where possible.
enum QueryCompiler {
    // MARK: Internal

    /// Compile a query to a filter closure
    static func compile(_ query: ParsedQuery) -> (QSO) -> Bool {
        if query.isEmpty {
            return { _ in true }
        }
        return compileExpression(query.expression)
    }

    /// Compile to both a basic predicate (for fetch) and a detailed filter (for refinement)
    ///
    /// The predicate handles simple indexed cases; the filter handles everything.
    /// Use the predicate to reduce the initial fetch, then apply the filter.
    static func compileWithPredicate(_ query: ParsedQuery) -> CompiledQuery {
        if query.isEmpty {
            return CompiledQuery(
                predicate: nil,
                filter: { _ in true },
                sortDescriptors: [SortDescriptor(\QSO.timestamp, order: .reverse)]
            )
        }

        let filter = compileExpression(query.expression)

        // Extract simple predicates for indexed fields where possible
        let predicate = extractPredicate(query.expression)

        return CompiledQuery(
            predicate: predicate,
            filter: filter,
            sortDescriptors: [SortDescriptor(\QSO.timestamp, order: .reverse)]
        )
    }

    // MARK: Private

    // MARK: - Expression Compilation

    private static func compileExpression(_ expr: QueryExpression) -> (QSO) -> Bool {
        switch expr {
        case .empty:
            return { _ in true }

        case let .term(term):
            return compileTerm(term)

        case let .and(expressions):
            let filters = expressions.map { compileExpression($0) }
            return { qso in filters.allSatisfy { $0(qso) } }

        case let .or(expressions):
            let filters = expressions.map { compileExpression($0) }
            return { qso in filters.contains { $0(qso) } }

        case let .not(inner):
            let filter = compileExpression(inner)
            return { qso in !filter(qso) }
        }
    }

    private static func compileTerm(_ term: QueryTerm) -> (QSO) -> Bool {
        if let field = term.field {
            compileFieldTerm(field: field, condition: term.condition)
        } else {
            compileBareSearchTerm(condition: term.condition)
        }
    }

    private static func compileFieldTerm(field: QueryField, condition: TermCondition) -> (QSO) ->
        Bool
    {
        switch field {
        case .callsign:
            compileStringMatch(condition) { $0.callsign }

        case .band:
            compileStringMatch(condition) { $0.band }

        case .mode:
            compileStringMatch(condition) { $0.mode }

        case .frequency:
            compileNumericMatch(condition) { $0.frequency }

        case .park:
            compileOptionalStringMatch(condition) { $0.parkReference }

        case .sota:
            compileOptionalStringMatch(condition) { $0.sotaRef }

        case .grid:
            compileOptionalStringMatch(condition) { $0.theirGrid }

        case .state:
            compileOptionalStringMatch(condition) { $0.state }

        case .country:
            compileOptionalStringMatch(condition) { $0.country }

        case .dxcc:
            compileOptionalIntMatch(condition) { $0.dxcc }

        case .name:
            compileOptionalStringMatch(condition) { $0.name }

        case .qth:
            compileOptionalStringMatch(condition) { $0.qth }

        case .notes:
            compileOptionalStringMatch(condition) { $0.notes }

        case .myCallsign:
            compileStringMatch(condition) { $0.myCallsign }

        case .myGrid:
            compileOptionalStringMatch(condition) { $0.myGrid }

        case .date,
             .after,
             .before:
            compileDateMatch(field: field, condition: condition)

        case .power:
            compileOptionalIntMatch(condition) { $0.power }

        case .confirmed:
            compileConfirmedMatch(condition)

        case .synced:
            compileSyncedMatch(condition)

        case .pending:
            compilePendingMatch(condition)

        case .source:
            compileSourceMatch(condition)
        }
    }

    // MARK: - String Matching

    private static func compileStringMatch(
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

    private static func compileOptionalStringMatch(
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

    // MARK: - Numeric Matching

    private static func compileNumericMatch(
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

    private static func compileOptionalIntMatch(
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

    // MARK: - Date Matching

    private static func compileDateMatch(field: QueryField, condition: TermCondition) -> (QSO) ->
        Bool
    {
        switch condition {
        case let .dateEquals(dateMatch):
            let (start, end) = dateMatch.resolve()
            return { $0.timestamp >= start && $0.timestamp < end }

        case let .dateAfter(dateMatch):
            let (start, _) = dateMatch.resolve()
            return { $0.timestamp >= start }

        case let .dateBefore(dateMatch):
            let (_, end) = dateMatch.resolve()
            return { $0.timestamp < end }

        case let .dateRange(startMatch, endMatch):
            let (start, _) = startMatch.resolve()
            let (_, end) = endMatch.resolve()
            return { $0.timestamp >= start && $0.timestamp < end }

        default:
            return { _ in true }
        }
    }

    // MARK: - Status Matching

    private static func compileConfirmedMatch(_ condition: TermCondition) -> (QSO) -> Bool {
        switch condition {
        case let .boolean(value):
            if value {
                // Confirmed on ANY service
                { $0.qrzConfirmed || $0.lotwConfirmed }
            } else {
                // Not confirmed anywhere
                { !$0.qrzConfirmed && !$0.lotwConfirmed }
            }

        case let .service(service):
            switch service {
            case .lotw:
                { $0.lotwConfirmed }
            case .qrz:
                { $0.qrzConfirmed }
            default:
                { _ in false } // Only LoTW and QRZ have confirmation
            }

        default:
            { _ in true }
        }
    }

    private static func compileSyncedMatch(_ condition: TermCondition) -> (QSO) -> Bool {
        switch condition {
        case let .boolean(value):
            if value {
                { $0.servicePresence.contains(where: \.isPresent) }
            } else {
                { !$0.servicePresence.contains(where: \.isPresent) }
            }

        case let .service(service):
            { $0.isPresent(in: service) }

        default:
            { _ in true }
        }
    }

    private static func compilePendingMatch(_ condition: TermCondition) -> (QSO) -> Bool {
        switch condition {
        case let .boolean(value):
            if value {
                { $0.servicePresence.contains(where: \.needsUpload) }
            } else {
                { !$0.servicePresence.contains(where: \.needsUpload) }
            }

        case let .service(service):
            { $0.needsUpload(to: service) }

        default:
            { _ in true }
        }
    }

    private static func compileSourceMatch(_ condition: TermCondition) -> (QSO) -> Bool {
        switch condition {
        case let .service(service):
            let importSource: ImportSource =
                switch service {
                case .qrz:
                    .qrz
                case .pota:
                    .pota
                case .lofi:
                    .lofi
                case .hamrs:
                    .hamrs
                case .lotw:
                    .lotw
                case .clublog:
                    .clublog
                }
            return { $0.importSource == importSource }

        case let .equals(value):
            if value.lowercased() == "manual" || value.lowercased() == "logger" {
                return { $0.importSource == .logger }
            }
            return { _ in false }

        default:
            return { _ in true }
        }
    }

    // MARK: - Bare Term (Multi-field Search)

    private static func compileBareSearchTerm(condition: TermCondition) -> (QSO) -> Bool {
        // Bare terms search across callsign, park, SOTA, and notes
        switch condition {
        case let .contains(value):
            let lowered = value.lowercased()
            return { qso in
                qso.callsign.lowercased().contains(lowered)
                    || (qso.parkReference?.lowercased().contains(lowered) ?? false)
                    || (qso.sotaRef?.lowercased().contains(lowered) ?? false)
                    || (qso.notes?.lowercased().contains(lowered) ?? false)
            }

        case let .equals(value):
            let lowered = value.lowercased()
            return { qso in
                qso.callsign.lowercased() == lowered
                    || qso.parkReference?.lowercased() == lowered
                    || qso.sotaRef?.lowercased() == lowered
            }

        case let .prefix(value):
            let lowered = value.lowercased()
            return { qso in
                qso.callsign.lowercased().hasPrefix(lowered)
                    || (qso.parkReference?.lowercased().hasPrefix(lowered) ?? false)
                    || (qso.sotaRef?.lowercased().hasPrefix(lowered) ?? false)
            }

        case let .suffix(value):
            let lowered = value.lowercased()
            return { qso in
                qso.callsign.lowercased().hasSuffix(lowered)
                    || (qso.parkReference?.lowercased().hasSuffix(lowered) ?? false)
                    || (qso.sotaRef?.lowercased().hasSuffix(lowered) ?? false)
            }

        default:
            return { _ in true }
        }
    }

    // MARK: - Predicate Extraction (for FetchDescriptor optimization)

    private static func extractPredicate(_ expression: QueryExpression) -> Predicate<QSO>? {
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

// MARK: - CompiledQuery

/// Compiled query with both predicate and filter
struct CompiledQuery {
    /// Optional predicate for FetchDescriptor (handles simple indexed cases)
    let predicate: Predicate<QSO>?

    /// Full filter closure (handles all cases)
    let filter: (QSO) -> Bool

    /// Sort descriptors
    let sortDescriptors: [SortDescriptor<QSO>]

    /// Build a FetchDescriptor using the predicate
    ///
    /// Note: We use the base !isHidden predicate always, and rely on post-fetch
    /// filtering for complex queries since SwiftData doesn't support runtime
    /// predicate composition.
    func fetchDescriptor(limit: Int? = nil) -> FetchDescriptor<QSO> {
        // Use query predicate if available, otherwise just filter hidden
        let finalPredicate = predicate ?? #Predicate<QSO> { !$0.isHidden }

        var descriptor = FetchDescriptor<QSO>(predicate: finalPredicate)
        descriptor.sortBy = sortDescriptors
        if let limit {
            descriptor.fetchLimit = limit
        }
        return descriptor
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
