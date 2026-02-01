import Foundation

// MARK: - ParsedQuery

/// Root node of a parsed query
struct ParsedQuery: Equatable {
    let expression: QueryExpression
    let sourceText: String

    /// Check if query is empty (matches everything)
    var isEmpty: Bool {
        if case .empty = expression {
            return true
        }
        return false
    }
}

// MARK: - QueryExpression

/// Query expression tree
indirect enum QueryExpression: Equatable {
    /// Empty query (matches all)
    case empty

    /// Single term (field match or bare term)
    case term(QueryTerm)

    /// Logical AND of expressions
    case and([QueryExpression])

    /// Logical OR of expressions
    case or([QueryExpression])

    /// Logical NOT of expression
    case not(QueryExpression)

    // MARK: Internal

    /// Flattens nested ANDs and ORs for easier processing
    var flattened: QueryExpression {
        switch self {
        case .empty,
             .term:
            return self

        case let .and(expressions):
            var flattened: [QueryExpression] = []
            for expr in expressions {
                let flat = expr.flattened
                if case let .and(nested) = flat {
                    flattened.append(contentsOf: nested)
                } else {
                    flattened.append(flat)
                }
            }
            if flattened.count == 1 {
                return flattened[0]
            }
            return .and(flattened)

        case let .or(expressions):
            var flattened: [QueryExpression] = []
            for expr in expressions {
                let flat = expr.flattened
                if case let .or(nested) = flat {
                    flattened.append(contentsOf: nested)
                } else {
                    flattened.append(flat)
                }
            }
            if flattened.count == 1 {
                return flattened[0]
            }
            return .or(flattened)

        case let .not(inner):
            return .not(inner.flattened)
        }
    }

    /// Extract all terms from the expression
    var allTerms: [QueryTerm] {
        switch self {
        case .empty:
            []
        case let .term(term):
            [term]
        case let .and(expressions),
             let .or(expressions):
            expressions.flatMap(\.allTerms)
        case let .not(inner):
            inner.allTerms
        }
    }

    /// Check if any positive (non-negated) term uses an indexed field
    var hasIndexedPositiveTerm: Bool {
        switch self {
        case .empty:
            false
        case let .term(term):
            term.field?.isIndexed ?? false
        case let .and(expressions),
             let .or(expressions):
            expressions.contains(where: \.hasIndexedPositiveTerm)
        case .not:
            false // Negated terms don't help with indexing
        }
    }

    /// Check if all terms are negated
    var isNegationOnly: Bool {
        switch self {
        case .empty:
            false
        case .term:
            false
        case let .and(expressions):
            expressions.allSatisfy(\.isNegationOnly)
        case let .or(expressions):
            expressions.allSatisfy(\.isNegationOnly)
        case .not:
            true
        }
    }
}

// MARK: - QueryTerm

/// A single search term
struct QueryTerm: Equatable {
    /// The field being searched (nil for bare terms that match multiple fields)
    let field: QueryField?

    /// The match condition
    let condition: TermCondition

    /// Source position for error reporting
    let position: SourcePosition
}

// MARK: - TermCondition

/// How a term matches values
enum TermCondition: Equatable {
    /// Exact match (case-insensitive for strings)
    case equals(String)

    /// Contains substring (case-insensitive)
    case contains(String)

    /// Prefix match (for wildcards like "W1*")
    case prefix(String)

    /// Suffix match (for wildcards like "*ABC") - slow!
    case suffix(String)

    /// Numeric comparison
    case greaterThan(Double)
    case lessThan(Double)
    case greaterThanOrEqual(Double)
    case lessThanOrEqual(Double)

    /// Range match (inclusive)
    case range(String, String)

    /// Numeric range match (inclusive)
    case numericRange(Double, Double)

    /// Date match
    case dateEquals(DateMatch)
    case dateAfter(DateMatch)
    case dateBefore(DateMatch)
    case dateRange(DateMatch, DateMatch)

    /// Boolean match (for confirmed:yes/no)
    case boolean(Bool)

    /// Service type match (for confirmed:lotw, synced:qrz, etc.)
    case service(ServiceType)

    // MARK: Internal

    /// The raw value for display purposes
    var displayValue: String {
        switch self {
        case let .equals(v),
             let .contains(v),
             let .prefix(v),
             let .suffix(v):
            v
        case let .greaterThan(n),
             let .lessThan(n),
             let .greaterThanOrEqual(n),
             let .lessThanOrEqual(n):
            String(n)
        case let .range(a, b):
            "\(a)..\(b)"
        case let .numericRange(a, b):
            "\(a)..\(b)"
        case let .dateEquals(d),
             let .dateAfter(d),
             let .dateBefore(d):
            d.description
        case let .dateRange(a, b):
            "\(a.description)..\(b.description)"
        case let .boolean(v):
            v ? "yes" : "no"
        case let .service(s):
            s.rawValue
        }
    }

    /// Whether this condition requires a full scan (no index help)
    var requiresFullScan: Bool {
        switch self {
        case .suffix,
             .contains:
            true
        default:
            false
        }
    }
}

// MARK: - DateMatch

/// Parsed date value
enum DateMatch: Equatable, CustomStringConvertible {
    /// Specific date
    case specific(Date)

    /// Relative date (e.g., "7d" = 7 days ago)
    case relative(days: Int)

    /// Today
    case today

    /// Yesterday
    case yesterday

    /// Year only (matches entire year)
    case year(Int)

    /// Year and month (matches entire month)
    case yearMonth(Int, Int)

    // MARK: Internal

    var description: String {
        switch self {
        case let .specific(date):
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        case let .relative(days):
            return "\(days)d"
        case .today:
            return "today"
        case .yesterday:
            return "yesterday"
        case let .year(year):
            return String(year)
        case let .yearMonth(year, month):
            return String(format: "%04d-%02d", year, month)
        }
    }

    /// Resolve to actual date range
    func resolve() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case let .specific(date):
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case let .relative(days):
            let start = calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: -days, to: now)!
            )
            return (start, now)

        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            let start = calendar.startOfDay(for: yesterday)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case let .year(year):
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            let start = calendar.date(from: components)!
            components.year = year + 1
            let end = calendar.date(from: components)!
            return (start, end)

        case let .yearMonth(year, month):
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            let start = calendar.date(from: components)!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
        }
    }
}
