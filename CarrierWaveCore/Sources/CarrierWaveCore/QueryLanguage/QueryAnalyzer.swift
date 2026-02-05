// swiftlint:disable function_body_length identifier_name

import Foundation

// MARK: - QueryAnalyzer

/// Analyzes a parsed query for performance characteristics
public enum QueryAnalyzer {
    // MARK: Public

    /// Analyze a query and return performance warnings
    public static func analyze(_ query: ParsedQuery, qsoCount: Int) -> QueryAnalysis {
        if query.isEmpty {
            return QueryAnalysis(
                warnings: [],
                estimatedCost: .indexed,
                usesIndex: true
            )
        }

        var warnings: [QueryWarning] = []
        let terms = query.expression.allTerms

        // Separate positive and negative terms
        let (positiveTerms, negatedTerms) = categorizeTerms(query.expression)

        // Check 1: No indexed fields in positive terms
        let indexedPositiveFields = positiveTerms.compactMap(\.field).filter(\.isIndexed)
        let usesIndex = !indexedPositiveFields.isEmpty

        if !usesIndex && qsoCount > 1_000 {
            warnings.append(
                QueryWarning(
                    severity: .high,
                    message: "This search scans all \(qsoCount.formatted()) QSOs",
                    suggestion: "Add a callsign, date, band, or mode filter"
                )
            )
        }

        // Check 2: Leading wildcards
        for term in terms {
            if case let .suffix(pattern) = term.condition {
                warnings.append(
                    QueryWarning(
                        severity: .high,
                        message: "Wildcard at start of '*\(pattern)' can't use index",
                        suggestion: "Use trailing wildcard instead: '\(pattern)*'"
                    )
                )
            }
        }

        // Check 3: Negation-only query
        if !positiveTerms.isEmpty || !negatedTerms.isEmpty {
            if positiveTerms.isEmpty, !negatedTerms.isEmpty {
                warnings.append(
                    QueryWarning(
                        severity: .high,
                        message: "Exclusion-only query must scan all records",
                        suggestion: "Add a positive filter like a date range"
                    )
                )
            }
        }

        // Check 4: Text scan fields (notes, name, qth)
        for term in positiveTerms {
            if let field = term.field, field.requiresTextScan {
                warnings.append(
                    QueryWarning(
                        severity: .medium,
                        message: "Searching '\(field.displayName)' scans all records",
                        suggestion: nil
                    )
                )
            }
        }

        // Check 5: Contains/substring matching on non-text fields
        for term in terms where term.field != nil {
            if case .contains = term.condition, let field = term.field, !field.requiresTextScan {
                warnings.append(
                    QueryWarning(
                        severity: .medium,
                        message: "Substring search on '\(field.displayName)' is slower than prefix",
                        suggestion: "Use '\(term.condition.displayValue)*' for prefix match"
                    )
                )
            }
        }

        // Check 6: Large dataset without date bounds
        let hasDateBound = positiveTerms.contains { term in
            guard let field = term.field else {
                return false
            }
            return field == .date || field == .after || field == .before
        }

        if !hasDateBound, qsoCount > 10_000, usesIndex {
            warnings.append(
                QueryWarning(
                    severity: .hint,
                    message: "Searching \(qsoCount.formatted()) QSOs",
                    suggestion: "Add 'after:30d' to search recent contacts only"
                )
            )
        }

        // Check 7: Frequency range queries
        let hasFrequencySearch = terms.contains { $0.field == .frequency }
        if hasFrequencySearch, qsoCount > 5_000, !hasDateBound {
            warnings.append(
                QueryWarning(
                    severity: .medium,
                    message: "Frequency searches may be slow on large datasets",
                    suggestion: "Add a date filter to reduce scan size"
                )
            )
        }

        // Determine overall cost
        let cost: QueryCost =
            if usesIndex {
                .indexed
            } else if hasDateBound {
                .bounded
            } else {
                .fullScan
            }

        // Deduplicate warnings by message
        let uniqueWarnings = Array(
            Dictionary(grouping: warnings, by: \.message).values.compactMap(\.first)
        )

        return QueryAnalysis(
            warnings: uniqueWarnings.sorted { $0.severity > $1.severity },
            estimatedCost: cost,
            usesIndex: usesIndex
        )
    }

    // MARK: Private

    /// Categorize terms into positive and negated
    private static func categorizeTerms(_ expression: QueryExpression)
        -> (positive: [QueryTerm], negated: [QueryTerm])
    {
        var positive: [QueryTerm] = []
        var negated: [QueryTerm] = []

        func walk(_ expr: QueryExpression, isNegated: Bool) {
            switch expr {
            case .empty:
                break
            case let .term(term):
                if isNegated {
                    negated.append(term)
                } else {
                    positive.append(term)
                }
            case let .and(exprs),
                 let .or(exprs):
                for e in exprs {
                    walk(e, isNegated: isNegated)
                }
            case let .not(inner):
                walk(inner, isNegated: !isNegated)
            }
        }

        walk(expression, isNegated: false)
        return (positive, negated)
    }
}

// MARK: - QueryAnalysis

/// Result of query analysis
public struct QueryAnalysis: Sendable {
    // MARK: Lifecycle

    public init(warnings: [QueryWarning], estimatedCost: QueryCost, usesIndex: Bool) {
        self.warnings = warnings
        self.estimatedCost = estimatedCost
        self.usesIndex = usesIndex
    }

    // MARK: Public

    public let warnings: [QueryWarning]
    public let estimatedCost: QueryCost
    public let usesIndex: Bool

    /// Whether to show a warning to the user
    public var shouldWarn: Bool {
        warnings.contains { $0.severity >= .medium }
    }

    /// Whether to require confirmation before executing
    public var requiresConfirmation: Bool {
        warnings.contains { $0.severity >= .high }
    }

    /// Highest severity warning
    public var maxSeverity: QueryWarning.Severity? {
        warnings.map(\.severity).max()
    }
}

// MARK: - QueryWarning

/// A performance warning for a query
public struct QueryWarning: Identifiable, Sendable {
    // MARK: Lifecycle

    public init(severity: Severity, message: String, suggestion: String?) {
        id = UUID()
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
    }

    // MARK: Public

    public enum Severity: Int, Comparable, Sendable {
        case hint = 0
        case medium = 1
        case high = 2

        // MARK: Public

        public var icon: String {
            switch self {
            case .hint: "lightbulb"
            case .medium: "bolt.fill"
            case .high: "exclamationmark.triangle.fill"
            }
        }

        public var color: String {
            switch self {
            case .hint: "blue"
            case .medium: "orange"
            case .high: "red"
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let id: UUID
    public let severity: Severity
    public let message: String
    public let suggestion: String?
}

// MARK: - QueryCost

/// Estimated query cost
public enum QueryCost: Comparable, Sendable {
    /// Uses database index, fast regardless of dataset size
    case indexed

    /// Full scan but bounded by date or limit
    case bounded

    /// Full table scan - warn user
    case fullScan

    // MARK: Public

    public var description: String {
        switch self {
        case .indexed: "Fast (indexed)"
        case .bounded: "Moderate (bounded scan)"
        case .fullScan: "Slow (full scan)"
        }
    }
}
