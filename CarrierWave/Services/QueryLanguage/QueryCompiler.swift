import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - QueryCompiler

/// Compiles a parsed query into a filter function for QSOs
///
/// Note: SwiftData's #Predicate macro doesn't support runtime construction,
/// so we compile to a closure-based filter. For indexed fields, we also
/// provide a FetchDescriptor with predicates where possible.
enum QueryCompiler {
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

    // MARK: - Expression Compilation

    static func compileExpression(_ expr: QueryExpression) -> (QSO) -> Bool {
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

    static func compileTerm(_ term: QueryTerm) -> (QSO) -> Bool {
        if let field = term.field {
            compileFieldTerm(field: field, condition: term.condition)
        } else {
            compileBareSearchTerm(condition: term.condition)
        }
    }

    static func compileFieldTerm(field: QueryField, condition: TermCondition) -> (QSO) ->
        Bool
    {
        switch field {
        case .callsign,
             .band,
             .mode,
             .myCallsign:
            compileStringFieldTerm(field: field, condition: condition)
        case .park,
             .sota,
             .grid,
             .state,
             .country,
             .name,
             .qth,
             .notes,
             .myGrid:
            compileOptionalStringFieldTerm(field: field, condition: condition)
        case .frequency:
            compileNumericMatch(condition) { $0.frequency }
        case .dxcc,
             .power:
            compileOptionalIntFieldTerm(field: field, condition: condition)
        case .date,
             .after,
             .before:
            compileDateMatch(field: field, condition: condition)
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
