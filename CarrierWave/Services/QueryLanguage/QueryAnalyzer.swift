import Foundation

/// Analyzes a parsed query for performance characteristics
struct QueryAnalyzer {
    /// Analyze a query and return performance warnings
    static func analyze(_ query: ParsedQuery, qsoCount: Int) -> QueryAnalysis {
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

        if !usesIndex && qsoCount > 1000 {
            warnings.append(QueryWarning(
                severity: .high,
                message: "This search scans all \(qsoCount.formatted()) QSOs",
                suggestion: "Add a callsign, date, band, or mode filter"
            ))
        }

        // Check 2: Leading wildcards
        for term in terms {
            if case let .suffix(pattern) = term.condition {
                warnings.append(QueryWarning(
                    severity: .high,
                    message: "Wildcard at start of '*\(pattern)' can't use index",
                    suggestion: "Use trailing wildcard instead: '\(pattern)*'"
                ))
            }
        }

        // Check 3: Negation-only query
        if !positiveTerms.isEmpty || !negatedTerms.isEmpty {
            if positiveTerms.isEmpty && !negatedTerms.isEmpty {
                warnings.append(QueryWarning(
                    severity: .high,
                    message: "Exclusion-only query must scan all records",
                    suggestion: "Add a positive filter like a date range"
                ))
            }
        }

        // Check 4: Text scan fields (notes, name, qth)
        for term in positiveTerms {
            if let field = term.field, field.requiresTextScan {
                warnings.append(QueryWarning(
                    severity: .medium,
                    message: "Searching '\(field.displayName)' scans all records",
                    suggestion: nil
                ))
            }
        }

        // Check 5: Contains/substring matching on non-text fields
        for term in terms where term.field != nil {
            if case .contains = term.condition, let field = term.field, !field.requiresTextScan {
                warnings.append(QueryWarning(
                    severity: .medium,
                    message: "Substring search on '\(field.displayName)' is slower than prefix",
                    suggestion: "Use '\(term.condition.displayValue)*' for prefix match"
                ))
            }
        }

        // Check 6: Large dataset without date bounds
        let hasDateBound = positiveTerms.contains { term in
            guard let field = term.field else {
                return false
            }
            return field == .date || field == .after || field == .before
        }

        if !hasDateBound && qsoCount > 10000 && usesIndex {
            warnings.append(QueryWarning(
                severity: .hint,
                message: "Searching \(qsoCount.formatted()) QSOs",
                suggestion: "Add 'after:30d' to search recent contacts only"
            ))
        }

        // Check 7: Frequency range queries
        let hasFrequencySearch = terms.contains { $0.field == .frequency }
        if hasFrequencySearch && qsoCount > 5000 && !hasDateBound {
            warnings.append(QueryWarning(
                severity: .medium,
                message: "Frequency searches may be slow on large datasets",
                suggestion: "Add a date filter to reduce scan size"
            ))
        }

        // Determine overall cost
        let cost: QueryCost
        if usesIndex {
            cost = .indexed
        } else if hasDateBound {
            cost = .bounded
        } else {
            cost = .fullScan
        }

        // Deduplicate warnings by message
        let uniqueWarnings = Array(Dictionary(grouping: warnings, by: \.message).values.compactMap(\.first))

        return QueryAnalysis(
            warnings: uniqueWarnings.sorted { $0.severity > $1.severity },
            estimatedCost: cost,
            usesIndex: usesIndex
        )
    }

    /// Categorize terms into positive and negated
    private static func categorizeTerms(_ expression: QueryExpression) -> (positive: [QueryTerm], negated: [QueryTerm]) {
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
            case let .and(exprs), let .or(exprs):
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

/// Result of query analysis
struct QueryAnalysis {
    let warnings: [QueryWarning]
    let estimatedCost: QueryCost
    let usesIndex: Bool

    /// Whether to show a warning to the user
    var shouldWarn: Bool {
        warnings.contains { $0.severity >= .medium }
    }

    /// Whether to require confirmation before executing
    var requiresConfirmation: Bool {
        warnings.contains { $0.severity >= .high }
    }

    /// Highest severity warning
    var maxSeverity: QueryWarning.Severity? {
        warnings.map(\.severity).max()
    }
}

/// A performance warning for a query
struct QueryWarning: Identifiable {
    let id = UUID()
    let severity: Severity
    let message: String
    let suggestion: String?

    enum Severity: Int, Comparable {
        case hint = 0
        case medium = 1
        case high = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var icon: String {
            switch self {
            case .hint: "lightbulb"
            case .medium: "bolt.fill"
            case .high: "exclamationmark.triangle.fill"
            }
        }

        var color: String {
            switch self {
            case .hint: "blue"
            case .medium: "orange"
            case .high: "red"
            }
        }
    }
}

/// Estimated query cost
enum QueryCost: Comparable {
    /// Uses database index, fast regardless of dataset size
    case indexed

    /// Full scan but bounded by date or limit
    case bounded

    /// Full table scan - warn user
    case fullScan

    var description: String {
        switch self {
        case .indexed: "Fast (indexed)"
        case .bounded: "Moderate (bounded scan)"
        case .fullScan: "Slow (full scan)"
        }
    }
}
