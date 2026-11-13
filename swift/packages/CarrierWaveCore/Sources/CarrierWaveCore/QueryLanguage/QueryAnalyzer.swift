import Foundation

// MARK: - QueryAnalyzer

/// Namespace for query analysis. The analysis itself now runs in the shared Rust
/// core (`cw-domain`) — see `QueryAnalyzer+Rust.swift` (`analyzeViaRust`). The old
/// Swift AST analyzer was retired when the whole `.cwquery` engine (parser + AST +
/// compiler) moved to Rust; only these result DTOs remain, populated from the FFI.
public enum QueryAnalyzer {}

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
